#!/usr/bin/env bash
set -Eeuo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo/config/release.env"
dir="$repo/dist"
name="sillage-$SILLAGE_VERSION-amd64.iso"
tag="sillage-$SILLAGE_VERSION-build-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:?}"
files=("$dir/$name.sha256" "$dir/filesystem.manifest" "$dir/build-info.txt")

if (( $(stat -c %s "$dir/$name") >= 2147483648 )); then
    parts=$(mktemp -d)
    trap 'rm -rf -- "$parts"' EXIT
    split -b 1900M -d -a 3 "$dir/$name" "$parts/$name.part-"
    files+=("$parts/$name.part-"* "$repo/tools/Assembler-ISO.ps1")
else
    files+=("$dir/$name")
fi

url=$(gh release create "$tag" --repo "$GITHUB_REPOSITORY" --draft --target "$GITHUB_SHA" \
    --title "Sillage $SILLAGE_VERSION — essai $GITHUB_RUN_NUMBER" \
    --notes 'Démarrage live UEFI validé en VM. Utiliser le mode « Essayer » sur l’ASUS.' \
    "${files[@]}")
printf '\n[Télécharger Sillage dans les pièces jointes du brouillon](%s)\n' "$url" >> "$GITHUB_STEP_SUMMARY"
