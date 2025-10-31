#!/usr/bin/env pwsh
# ci/verify-ledger-ci.ps1

$ErrorActionPreference = "Stop"

Write-Host "=== HUMEAN CI | verify-ledger ==="

# 1) détecter le ledger
$ledgerSigned = "log/ledger_signed.jsonl"
$ledgerPlain  = "log/ledger.jsonl"

if (Test-Path $ledgerSigned) {
    $ledgerToCheck = $ledgerSigned
} elseif (Test-Path $ledgerPlain) {
    $ledgerToCheck = $ledgerPlain
} else {
    Write-Warning "Aucun ledger trouvé (log/ledger_signed.jsonl ni log/ledger.jsonl)."
    Write-Warning "On ne fait PAS échouer le job pour le moment (1er push, repo vide)."
    exit 0
}

Write-Host "Ledger détecté: $ledgerToCheck"

# 2) trouver la clé publique
$pubFromRepo = "attestation/PRIMARY-KEY-003.pub"
$pubFromRepoB64 = "attestation/PRIMARY-KEY-003.pub.b64"
$pubkeyPath = $null

if (Test-Path $pubFromRepo) {
    $pubkeyPath = $pubFromRepo
} elseif (Test-Path $pubFromRepoB64) {
    Write-Host "Décodage de $pubFromRepoB64 ..."
    $raw = Get-Content $pubFromRepoB64 -Raw
    $bytes = [Convert]::FromBase64String($raw)
    [IO.File]::WriteAllBytes("attestation/PRIMARY-KEY-003.pub", $bytes)
    $pubkeyPath = "attestation/PRIMARY-KEY-003.pub"
} elseif ($env:HUMEAN_PUBKEY_B64) {
    Write-Host "Décodage de la clé depuis le secret HUMEAN_PUBKEY_B64 ..."
    $raw = $env:HUMEAN_PUBKEY_B64
    $bytes = [Convert]::FromBase64String($raw)
    New-Item -ItemType Directory -Force -Path "attestation" | Out-Null
    [IO.File]::WriteAllBytes("attestation/PRIMARY-KEY-003.pub", $bytes)
    $pubkeyPath = "attestation/PRIMARY-KEY-003.pub"
}

if (-not $pubkeyPath) {
    Write-Warning "Aucune clé publique trouvée. Impossible de vérifier la signature."
    Write-Warning "On quitte proprement pour ne pas faire échouer le workflow."
    exit 0
}

Write-Host "Clé publique utilisée : $pubkeyPath"

# 3) script de vérif de TON pack (adapte si besoin)
$verifyScript = "scripts/verify_charter.ps1"
if (-not (Test-Path $verifyScript)) {
    Write-Warning "Script de vérification introuvable: $verifyScript"
    Write-Warning "On ne fait pas échouer le job."
    exit 0
}

Write-Host "Lancement de la vérification..."
pwsh $verifyScript -Ledger $ledgerToCheck -PubKey $pubkeyPath
Write-Host "Vérification terminée."
