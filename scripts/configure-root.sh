#!/usr/bin/env bash
set -Eeuo pipefail

root=$1
repo=$SILLAGE_REPO
vendor_network_config="$root/usr/lib/NetworkManager/conf.d/10-globally-managed-devices.conf"
if [[ -f $vendor_network_config ]]; then
    printf 'NetworkManager Ubuntu (%s)\n' "${vendor_network_config#"$root"}"
    grep -E '^[[:space:]]*unmanaged-devices[[:space:]]*=' "$vendor_network_config" || true
fi
cp -a "$repo/rootfs/." "$root/"
network_config=$(chroot "$root" NetworkManager --print-config)
printf '%s\n' "$network_config" | grep -E '^\[keyfile\]|^unmanaged-devices[[:space:]]*=' || true
if grep -Eq '^unmanaged-devices[[:space:]]*=[[:space:]]*[^[:space:]]' <<< "$network_config"; then
    echo 'La configuration effective de NetworkManager contient encore une exclusion globale.' >&2
    exit 1
fi
install -m 0644 "$repo/rootfs/usr/share/icons/hicolor/scalable/apps/sillage.svg" \
    "$root/etc/calamares/branding/sillage/sillage.svg"
install -m 0644 "$repo/config/mozilla.sources" "$root/etc/apt/sources.list.d/mozilla.sources"
install -m 0644 "$repo/config/mozilla.pref" "$root/etc/apt/preferences.d/mozilla"
install -d "$root/etc/apt/keyrings"

mozilla_key="$root/etc/apt/keyrings/packages.mozilla.org.asc"
curl --fail --location --retry 4 --silent --show-error https://packages.mozilla.org/apt/repo-signing-key.gpg > "$mozilla_key"
fingerprint=$(gpg --batch --with-colons --show-keys "$mozilla_key" | awk -F: '$1 == "fpr" && !found++ {print $10}')
test "$fingerprint" = 35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3
chmod 0644 "$mozilla_key"

# mmdebstrap écrit ses sources à plusieurs endroits selon la version. La cible
# installée suit les dépôts de sécurité courants, pas l’instantané du build.
chroot "$root" env -u APT_CONFIG apt-get -o Dir::Etc::sourcelist=sources.list.d/mozilla.sources -o Dir::Etc::sourceparts=- \
    -o APT::Get::List-Cleanup=0 update
chroot "$root" env -u APT_CONFIG apt-get -y --no-install-recommends install firefox firefox-l10n-fr
rm -f "$root/etc/dpkg/dpkg.cfg.d/99sillage-staging-io"
chroot "$root" env -u APT_CONFIG apt-get clean
find "$root/etc/apt/sources.list.d" -maxdepth 1 -type f ! -name 'mozilla.sources' -delete
rm -f "$root/etc/apt/sources.list"
install -m 0644 "$repo/config/ubuntu.sources" "$root/etc/apt/sources.list.d/ubuntu.sources"
find "$root/var/lib/apt/lists" -maxdepth 1 -type f -delete

chmod 0755 "$root/etc/initramfs-tools/hooks/sillage-disk-guard" \
    "$root/etc/initramfs-tools/scripts/init-premount/sillage-protect" "$root"/usr/lib/sillage/* \
    "$root"/usr/local/bin/sillage-*
printf 'Europe/Paris\n' > "$root/etc/timezone"
ln -sf /usr/share/zoneinfo/Europe/Paris "$root/etc/localtime"
printf 'en_US.UTF-8 UTF-8\nfr_FR.UTF-8 UTF-8\n' > "$root/etc/locale.gen"
chroot "$root" locale-gen
printf 'LANG=fr_FR.UTF-8\n' > "$root/etc/default/locale"
printf 'sillage\n' > "$root/etc/hostname"
printf '127.0.0.1 localhost\n127.0.1.1 sillage\n::1 localhost ip6-localhost ip6-loopback\n' > "$root/etc/hosts"

chroot "$root" systemctl enable NetworkManager.service fstrim.timer apt-daily.timer apt-daily-upgrade.timer \
    sillage-live-session.service sillage-ci.service
chroot "$root" systemctl mask NetworkManager-wait-online.service
ln -sfn /usr/lib/systemd/system/lightdm.service "$root/etc/systemd/system/display-manager.service"
chroot "$root" env DEBIAN_FRONTEND=noninteractive prime-select on-demand
chroot "$root" env CASPER_GENERATE_UUID=1 update-initramfs -u -k all
printf 'Sillage %s\n' "$SILLAGE_VERSION" > "$root/etc/sillage-release"
rm -f "$root/etc/resolv.conf"
ln -s /run/systemd/resolve/stub-resolv.conf "$root/etc/resolv.conf"
: > "$root/etc/machine-id"
rm -f "$root/var/lib/dbus/machine-id" "$root/var/lib/systemd/random-seed"
ln -s /etc/machine-id "$root/var/lib/dbus/machine-id"
