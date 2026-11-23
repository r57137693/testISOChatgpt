[CmdletBinding()]
param([string]$Directory = (Get-Location).Path)

$ErrorActionPreference = 'Stop'
$folder = (Resolve-Path -LiteralPath $Directory).Path
$manifest = @(Get-ChildItem -LiteralPath $folder -File -Filter 'sillage-*-amd64.iso.sha256')
if ($manifest.Count -ne 1) { throw 'Place le fichier SHA-256 et toutes les parties dans un dossier vide.' }

$line = (Get-Content -LiteralPath $manifest[0].FullName -Raw).Trim()
if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*?(sillage-[0-9.]+-amd64\.iso)$') {
    throw 'Le fichier SHA-256 ne correspond pas au format Sillage.'
}
$expected = $Matches[1]
$name = $Matches[2]
$target = Join-Path $folder $name
if (Test-Path -LiteralPath $target) { throw "Le fichier existe deja : $target" }

$parts = @(Get-ChildItem -LiteralPath $folder -File -Filter "$name.part-*" | Sort-Object Name)
if ($parts.Count -lt 2) { throw 'Il manque des parties de l ISO.' }
for ($index = 0; $index -lt $parts.Count; $index++) {
    $partName = '{0}.part-{1:D3}' -f $name, $index
    if ($parts[$index].Name -ne $partName) { throw "Partie manquante ou mal nommee : $partName" }
}

$temporary = "$target.partial-$([Guid]::NewGuid().ToString('N'))"
try {
    $output = [System.IO.File]::Open($temporary, 'CreateNew', 'Write')
    try {
        foreach ($part in $parts) {
            $inputPart = [System.IO.File]::OpenRead($part.FullName)
            try { $inputPart.CopyTo($output) } finally { $inputPart.Dispose() }
        }
    } finally { $output.Dispose() }

    if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $expected) {
        throw 'La somme SHA-256 a echoue. Verifie que toutes les parties ont ete telechargees.'
    }
    [System.IO.File]::Move($temporary, $target)
    Write-Output $target
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
}
