#!/usr/bin/env bash
set -Eeuo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
for script in scripts/*.sh config/release.env; do bash -n "$script"; done
for script in rootfs/usr/lib/sillage/* rootfs/usr/local/bin/sillage-* \
    rootfs/etc/initramfs-tools/hooks/* rootfs/etc/initramfs-tools/scripts/init-premount/*; do
    dash -n "$script"
done
grub-script-check config/grub.cfg
python3 - <<'PY'
from pathlib import Path
from xml.etree import ElementTree
import yaml

root = Path('rootfs')
for path in (*root.rglob('*.xml'), *root.rglob('*.svg')):
    ElementTree.parse(path)
for path in (*root.joinpath('etc/calamares').rglob('*.conf'), *root.rglob('*.desc'),
             *Path('.github/workflows').glob('*.yml')):
    data = yaml.safe_load(path.read_text(encoding='utf-8'))
    assert isinstance(data, dict), path
    if path.name == 'build-sillage.yml':
        assert 'workflow_dispatch' in data.get('on', data.get(True, {})), path
        assert 'iso' in data['jobs'], path
for path in (*Path('scripts').glob('*.sh'), *root.joinpath('etc/initramfs-tools').rglob('*')):
    if path.is_file():
        assert b'\r' not in path.read_bytes(), path
PY
find rootfs -name '*.desktop' -print0 | xargs -0r desktop-file-validate
echo 'Sources Sillage : vérifications statiques réussies.'
