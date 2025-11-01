#!/usr/bin/env pwsh
# ci/build-merkle-ledger.ps1
# Construit une racine de Merkle à partir du ledger HUMEAN

$ErrorActionPreference = "Stop"

Write-Host "=== HUMEAN | build merkle ledger ==="

# 1) trouver le ledger
$ledgerSigned = "log/ledger_signed.jsonl"
$ledgerPlain  = "log/ledger.jsonl"
$ledgerPath   = $null

if (Test-Path $ledgerSigned) {
    $ledgerPath = $ledgerSigned
} elseif (Test-Path $ledgerPlain) {
    $ledgerPath = $ledgerPlain
} else {
    Write-Warning "⚠️ Aucun ledger trouvé (log/ledger_signed.jsonl ni log/ledger.jsonl). Merkle ignoré."
    exit 0
}

Write-Host "→ Ledger utilisé : $ledgerPath"

# 2) lire toutes les lignes
$lines = Get-Content $ledgerPath -Encoding UTF8
if (-not $lines -or $lines.Count -eq 0) {
    Write-Warning "⚠️ Ledger vide, rien à merkliser."
    exit 0
}

# fonction utilitaire pour SHA256 -> hex
function Get-Sha256Hex([byte[]]$data) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($data)
    return (($hash | ForEach-Object ToString x2) -join '').ToLower()
}

# 3) on crée la liste des "feuilles" = hash de chaque ligne brute
$leaves = @()
foreach ($line in $lines) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($line)
    $h = Get-Sha256Hex $bytes
    $leaves += $h
}

Write-Host "→ $($leaves.Count) feuilles Merkle."

# 4) fonction pour construire l'arbre
function Build-MerkleRoot([string[]]$hashes) {
    if ($hashes.Count -eq 1) {
        return $hashes[0]
    }

    $nextLevel = @()

    for ($i = 0; $i -lt $hashes.Count; $i += 2) {
        $left = $hashes[$i]
        $right = $null
        if ($i + 1 -lt $hashes.Count) {
            $right = $hashes[$i + 1]
        } else {
            # si impair, on duplique la dernière feuille
            $right = $left
        }

        $concat = [Text.Encoding]::UTF8.GetBytes($left + $right)
        $parent = Get-Sha256Hex $concat
        $nextLevel += $parent
    }

    return Build-MerkleRoot $nextLevel
}

$root = Build-MerkleRoot $leaves

Write-Host "✅ Merkle root : $root"

# 5) écrire la racine dans out/...
New-Item -ItemType Directory -Force -Path "out" | Out-Null
$rootObj = [ordered]@{
    project    = "HUMEAN"
    version    = "v1.3"
    timestamp  = (Get-Date).ToString("s")
    ledger     = $ledgerPath
    merkleRoot = $root
    leaves     = $leaves.Count
}
$outPath = "out/merkle_root.json"
($rootObj | ConvertTo-Json -Depth 5) | Set-Content -Path $outPath -Encoding UTF8
Write-Host "→ racine écrite dans $outPath"

# 6) journaliser dans log/merkle.jsonl
New-Item -ItemType Directory -Force -Path "log" | Out-Null
$logEntry = $rootObj | ConvertTo-Json -Compress
Add-Content -Path "log/merkle.jsonl" -Value $logEntry

Write-Host "✅ Merkle log mis à jour (log/merkle.jsonl)"
Write-Host "=== FIN HUMEAN | build merkle ledger ==="
