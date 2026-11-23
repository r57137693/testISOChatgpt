#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo/config/release.env"
[[ $EUID == 0 && $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
    printf '%s\n' 'Exécuter via sudo sur Linux x86_64.' >&2
    exit 1
}
for dependency in mmdebstrap xorriso mksquashfs modinfo curl gpg grub-script-check dpkg-query lsinitramfs unmkinitramfs; do
    command -v "$dependency" >/dev/null || { echo "Outil manquant : $dependency" >&2; exit 1; }
done
export SILLAGE_REPO="$repo"
export SILLAGE_VERSION UBUNTU_SUITE
snapshot=${SILLAGE_SNAPSHOT:-$DEFAULT_APT_SNAPSHOT}
[[ $snapshot == current || $snapshot =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || {
    echo 'SILLAGE_SNAPSHOT doit être current ou une date UTC AAAAMMJJThhmmssZ.' >&2
    exit 1
}
export SILLAGE_BUILD_SNAPSHOT="$snapshot"

output=$(realpath -m -- "${1:-$repo/dist}")
if [[ ! -d $output && -n ${SUDO_UID:-} && -n ${SUDO_GID:-} ]]; then
    install -d -o "$SUDO_UID" -g "$SUDO_GID" -- "$output"
else
    mkdir -p -- "$output"
fi
work=$(mktemp -d "${SILLAGE_WORKDIR:-/var/tmp}/sillage.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
trap 'echo "Échec du build à la ligne $LINENO (état $?)." >&2' ERR
root="$work/root"
stage="$work/iso"
mkdir -p "$stage/casper" "$stage/boot/grub" "$stage/.disk"

if [[ $snapshot == current ]]; then
    archive=https://archive.ubuntu.com/ubuntu
    security=https://security.ubuntu.com/ubuntu
else
    archive="https://snapshot.ubuntu.com/ubuntu/$snapshot"
    security="$archive"
fi
keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg
test -s "$keyring"
cat > "$work/build.sources" <<EOF
Types: deb
URIs: $archive
Suites: $UBUNTU_SUITE $UBUNTU_SUITE-updates
Components: main restricted universe multiverse
Architectures: amd64
Signed-By: $keyring

Types: deb
URIs: $security
Suites: $UBUNTU_SUITE-security
Components: main restricted universe multiverse
Architectures: amd64
Signed-By: $keyring
EOF

echo '==> Construction du système Ubuntu et du bureau Sillage'
packages=$(tr '\n' ' ' < "$repo/config/packages.txt" | xargs | tr ' ' ',')
mmdebstrap --mode=root --format=directory --variant=minbase --architectures=amd64 \
    --aptopt='Acquire::Retries "3"' --include="$packages" \
    --essential-hook='install -d "$1/etc/dpkg/dpkg.cfg.d" && printf "%s\n" force-unsafe-io > "$1/etc/dpkg/dpkg.cfg.d/99sillage-staging-io"' \
    --customize-hook='bash "$SILLAGE_REPO/scripts/configure-root.sh" "$1"' \
    "$UBUNTU_SUITE" "$root" "$work/build.sources"

mapfile -t kernels < <(find "$root/boot" -maxdepth 1 -type f -name 'vmlinuz-*-generic' | sort -V)
[[ ${#kernels[@]} == 1 ]] || { echo 'Le build attend un seul noyau Ubuntu generic.' >&2; exit 1; }
kernel=${kernels[0]##*/vmlinuz-}
test -s "$root/boot/initrd.img-$kernel"
signer=$(modinfo -b "$root" -k "$kernel" -F signer nvidia)
[[ -n $signer ]] || { echo 'Le module NVIDIA du noyau ISO doit être signé.' >&2; exit 1; }
if chroot "$root" dpkg-query -W -f='${db:Status-Status}\n' nvidia-dkms-580 2>/dev/null | grep -qx installed; then
    echo 'Le module NVIDIA précompilé doit remplacer DKMS.' >&2
    exit 1
fi
lsinitramfs "$root/boot/initrd.img-$kernel" > "$work/initramfs-files"
grep -q 'scripts/init-premount/sillage-protect' "$work/initramfs-files"
grep -q 'etc/udev/rules.d/61-sillage-live-disks.rules' "$work/initramfs-files"
unmkinitramfs "$root/boot/initrd.img-$kernel" "$work/initrd-extract"
mapfile -t uuid_configs < <(find "$work/initrd-extract" -type f -path '*/conf/uuid.conf')
[[ ${#uuid_configs[@]} == 1 ]] || { echo 'UUID du support Casper introuvable.' >&2; exit 1; }
install -m 0644 "${uuid_configs[0]}" "$stage/.disk/casper-uuid-generic"
rm -rf -- "$work/initrd-extract"

install -m 0644 "${kernels[0]}" "$stage/casper/vmlinuz"
install -m 0644 "$root/boot/initrd.img-$kernel" "$stage/casper/initrd"
chroot "$root" dpkg-query -W -f='${Package}\t${Version}\n' | sort > "$stage/casper/filesystem.manifest"
du -sx --block-size=1 "$root" | cut -f1 > "$stage/casper/filesystem.size"
echo '==> Compression SquashFS en Zstandard'
mksquashfs "$root" "$stage/casper/filesystem.squashfs" -noappend -comp zstd -Xcompression-level 10 \
    -processors "${SILLAGE_SQUASHFS_JOBS:-4}" -no-progress
rm -rf -- "$root"

echo '==> Préparation du support UEFI et de l’ISO hybride'
bootstrap="$work/$BOOTSTRAP_ISO"
curl --fail --location --retry 4 --silent --show-error "$BOOTSTRAP_URL/$BOOTSTRAP_ISO" -o "$bootstrap"
printf '%s  %s\n' "$BOOTSTRAP_SHA256" "$bootstrap" | sha256sum --check
install -m 0644 "$repo/config/grub.cfg" "$stage/boot/grub/grub.cfg"
grub-script-check "$stage/boot/grub/grub.cfg"
echo "Sillage $SILLAGE_VERSION amd64" > "$stage/.disk/info"
(cd "$stage" && find casper boot .disk -type f -print0 | sort -z | xargs -0 md5sum) > "$stage/md5sum.txt"

name="sillage-$SILLAGE_VERSION-amd64.iso"
iso="$work/$name"
xorriso -abort_on FAILURE -indev "$bootstrap" -outdev "$iso" \
    -overwrite on -rm_r /casper /.disk -- \
    -map "$stage/casper" /casper \
    -map "$stage/boot/grub/grub.cfg" /boot/grub/grub.cfg \
    -map "$stage/boot/grub/grub.cfg" /boot/grub/loopback.cfg \
    -map "$stage/.disk" /.disk \
    -map "$stage/md5sum.txt" /md5sum.txt \
    -boot_image any replay -commit -end
xorriso -abort_on FAILURE -indev "$iso" -report_el_torito plain -report_system_area plain \
    > "$work/boot-layout.txt" 2>&1
grep -qi 'UEFI' "$work/boot-layout.txt"
grep -qi 'GPT' "$work/boot-layout.txt"
{
    printf 'sillage=%s\nubuntu=%s\nsnapshot=%s\nkernel=%s\nnvidia_signer=%s\nboot_template_sha256=%s\n' \
        "$SILLAGE_VERSION" "$UBUNTU_SUITE" "$snapshot" "$kernel" "$signer" "$BOOTSTRAP_SHA256"
    cat "$work/boot-layout.txt"
} > "$work/build-info.txt"
(cd "$work" && sha256sum "$name" > "$name.sha256")
install -m 0644 "$iso" "$work/$name.sha256" "$stage/casper/filesystem.manifest" "$work/build-info.txt" "$output/"
if [[ -n ${SUDO_UID:-} && -n ${SUDO_GID:-} ]]; then
    chown "$SUDO_UID:$SUDO_GID" "$output"/{"$name","$name.sha256",filesystem.manifest,build-info.txt}
fi
printf 'ISO : %s/%s\n' "$output" "$name"
