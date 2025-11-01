#!/usr/bin/env pwsh
# ci/make-attestation-pack.ps1
# Construit un pack d'attestation HUMEAN + MERKLE

$ErrorActionPreference = "Stop"

Write-Host "=== HUMEAN | build attestation pack (with Merkle) ==="

New-Item -ItemType Directory -Force -Path "out" | Out-Null

# fichiers "classiques"
$charter      = "charter_v1_3.json"
$ledgerSigned = "log/ledger_signed.jsonl"
$pubkey       = "attestation/PRIMARY-KEY-003.pub"

$files = @()
if (Test-Path $charter)      { $files += $charter }
if (Test-Path $ledgerSigned) { $files += $ledgerSigned }
if (Test-Path $pubkey)       { $files += $pubkey }

# 1) essayer de récupérer la Merkle root si le job précédent l'a produite
$merklePath = "out/merkle_root.json"
$merkleObj  = $null

if (Test-Path $merklePath) {
    Write-Host "→ Merkle root trouvée dans $merklePath"
    $merkleObj = Get-Content $merklePath -Raw | ConvertFrom-Json
} else {
    Write-Warning "⚠️ Pas de Merkle root trouvée, on va essayer de la générer à la volée..."
    if (Test-Path "ci/build-merkle-ledger.ps1") {
        pwsh ./ci/build-merkle-ledger.ps1
        if (Test-Path $merklePath) {
            $merkleObj = Get-Content $merklePath -Raw | ConvertFrom-Json
        }
    }
}

# 2) on prépare le manifest
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
        name   = $f
        sha256 = $hashHex
    }
}

# 3) si on a une Merkle root -> on l’inclut
if ($merkleObj -and $merkleObj.merkleRoot) {
    $manifest.merkle = @{
        root     = $merkleObj.merkleRoot
        ledger   = $merkleObj.ledger
        leaves   = $merkleObj.leaves
        ts       = $merkleObj.timestamp
    }
} else {
    $manifest.merkle = $null
}

# 4) signer le manifest si clé privée présente
$priv = "attestation/PRIMARY-KEY-003.priv"
if (Test-Path $priv) {
    try {
        $manifestJson = ($manifest | ConvertTo-Json -Depth 6)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $mhash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($manifestJson))

        try {
            $privRaw = Get-Content $priv -Raw
            $privBytes = [Convert]::FromBase64String($privRaw.Trim())
        } catch {
            $privBytes = [IO.File]::ReadAllBytes($priv)
        }

        $sig = [System.Security.Cryptography.Ed25519]::Sign($mhash, $privBytes)
        $manifest.signature  = [Convert]::ToBase64String($sig)
        $manifest.sig_method = "ed25519-dotnet"
    } catch {
        Write-Warning "⚠️ impossible de signer le manifest (clé non compatible)."
        $manifest.sig_method = "none"
    }
} else {
    $manifest.sig_method = "none"
}

# 5) écrire le manifest
$manifestPath = "out/manifest.json"
($manifest | ConvertTo-Json -Depth 6) | Set-Content -Path $manifestPath -Encoding UTF8

# 6) construire le zip
$stamp = (Get-Date -Format "yyyyMMdd-HHmmss")
$zipName = "out/humean-attestation-$stamp.zip"

# on ajoute aussi la merkle root si présente
$toZip = @($manifestPath) + $files
if (Test-Path $merklePath) {
    $toZip += $merklePath
}

Compress-Archive -Path $toZip -DestinationPath $zipName -Force

Write-Host "✅ pack généré : $zipName"
Write-Host "=== FIN HUMEAN | build attestation pack (with Merkle) ==="
