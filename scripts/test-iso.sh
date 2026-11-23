#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

iso=$(realpath -- "${1:?Usage: bash scripts/test-iso.sh /chemin/sillage.iso [journal]}")
log=$(realpath -m -- "${2:-$(dirname -- "$iso")/uefi-boot.log}")
test -s "$iso"
work=$(mktemp -d)
vm_pid=
cleanup() {
    if [[ -n $vm_pid ]]; then kill "$vm_pid" 2>/dev/null || true; wait "$vm_pid" 2>/dev/null || true; fi
    rm -rf -- "$work"
}
trap cleanup EXIT

firmware=${SILLAGE_OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.ms.fd}
variables=${SILLAGE_OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.ms.fd}
test -r "$firmware" && test -r "$variables"
cp -- "$variables" "$work/vars.fd"
truncate -s 32M "$work/witness.img"
printf 'label: gpt\nstart=2048, size=32768, type=linux\n' | sfdisk "$work/witness.img"
mkfs.ext4 -F -q -b 4096 -E offset=1048576 "$work/witness.img" 4096
sha256sum "$work/witness.img" > "$work/witness.sha256"
mkdir -p -- "$(dirname -- "$log")"
: > "$log"

qemu-system-x86_64 -machine q35,smm=on -accel tcg,thread=multi -cpu max -smp 2 -m 4096 \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$firmware" \
    -drive "if=pflash,format=raw,unit=1,file=$work/vars.fd" \
    -drive "if=none,id=stick,format=raw,snapshot=on,file=$iso" \
    -device qemu-xhci -device usb-storage,drive=stick,removable=on,bootindex=1 \
    -drive "if=none,id=witness,format=raw,file=$work/witness.img" \
    -device virtio-blk-pci,drive=witness,bootindex=2 \
    -fw_cfg name=opt/org.sillage.ci,string=1 \
    -qmp "unix:$work/monitor.sock,server=on,wait=off" \
    -display none -vga std -serial "file:$log" -nic none -no-reboot \
    > "$log.qemu" 2>&1 &
vm_pid=$!

for ((attempt=0; attempt<150; attempt++)); do
    if grep -q SILLAGE_LIVE_OK "$log"; then
        kill "$vm_pid"
        wait "$vm_pid" || true
        vm_pid=
        sha256sum --check "$work/witness.sha256"
        cat "$log"
        exit 0
    fi
    if grep -q SILLAGE_CI_FAILED "$log" || ! kill -0 "$vm_pid" 2>/dev/null; then break; fi
    sleep 3
done
if [[ -S $work/monitor.sock ]]; then
    python3 - "$work/monitor.sock" "$log.ppm" <<'PY' || true
import json
import socket
import sys

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as monitor:
    monitor.settimeout(4)
    monitor.connect(sys.argv[1])
    with monitor.makefile('rwb') as channel:
        channel.readline()
        for command in (
            {'execute': 'qmp_capabilities'},
            {'execute': 'screendump', 'arguments': {'filename': sys.argv[2]}},
        ):
            channel.write((json.dumps(command) + '\n').encode())
            channel.flush()
            while line := channel.readline():
                result = json.loads(line)
                if 'error' in result:
                    raise RuntimeError(result['error'])
                if 'return' in result:
                    break
PY
fi
cat "$log.qemu" "$log" >&2
echo 'Le démarrage USB UEFI protégé n’a pas été validé.' >&2
exit 1
