#!/usr/bin/env pwsh
# ci/make-attestation-pack.ps1

$ErrorActionPreference = "Stop"

Write-Host "=== HUMEAN | build attestation pack ==="

# dossiers
New-Item -ItemType Directory -Force -Path "out" | Out-Null

# fichiers sources
$charter = "charter_v1_3.json"
$ledgerSigned = "log/ledger_signed.jsonl"
$pubkey = "attestation/PRIMARY-KEY-003.pub"

# on accepte l’absence de certains, mais on note tout dans le manifest
$files = @()

if (Test-Path $charter)      { $files += $charter }
if (Test-Path $ledgerSigned) { $files += $ledgerSigned }
if (Test-Path $pubkey)       { $files += $pubkey }

# petit manifest json
$manifest = [ordered]@{
    project   = "HUMEAN"
    version   = "v1.3"
    timestamp = (Get-Date).ToString("s")
    files     = @()
}

foreach ($f in $files) {
    $bytes = [IO.File]::ReadAllBytes($f)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    $hashHex = ($hash | ForEach-Object ToString x2) -join ''
    $manifest.files += @{
        name = $f
        sha256 = $hashHex
    }
}

# essayer de signer le manifest avec ta clé privée si présente
$priv = "attestation/PRIMARY-KEY-003.priv"
if (Test-Path $priv) {
    try {
        $manifestJson = ($manifest | ConvertTo-Json -Depth 5)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $mhash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($manifestJson))

        try {
            $privRaw = Get-Content $priv -Raw
            $privBytes = [Convert]::FromBase64String($privRaw.Trim())
        } catch {
            $privBytes = [IO.File]::ReadAllBytes($priv)
        }

        $sig = [System.Security.Cryptography.Ed25519]::Sign($mhash, $privBytes)
        $manifest.signature = [Convert]::ToBase64String($sig)
        $manifest.sig_method = "ed25519-dotnet"
    } catch {
        $manifest.sig_method = "none"
    }
} else {
    $manifest.sig_method = "none"
}

$manifestPath = "out/manifest.json"
($manifest | ConvertTo-Json -Depth 5) | Set-Content -Path $manifestPath -Encoding UTF8

# construire le pack
$stamp = (Get-Date -Format "yyyyMMdd-HHmmss")
$zipName = "out/humean-attestation-$stamp.zip"

# on crée une liste réelle de fichiers à zipper
$toZip = @($manifestPath) + $files
Compress-Archive -Path $toZip -DestinationPath $zipName -Force

Write-Host "✅ pack généré : $zipName"
