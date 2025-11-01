#!/usr/bin/env pwsh
# ci/build-merkle-proofs.ps1
# Génère une preuve d'inclusion Merkle par ligne de ledger

$ErrorActionPreference = "Stop"

Write-Host "=== HUMEAN | build merkle proofs ==="

# 1) trouver le ledger
$ledgerSigned = "log/ledger_signed.jsonl"
$ledgerPlain  = "log/ledger.jsonl"
$ledgerPath   = $null

if (Test-Path $ledgerSigned) {
    $ledgerPath = $ledgerSigned
} elseif (Test-Path $ledgerPlain) {
    $ledgerPath = $ledgerPlain
} else {
    Write-Warning "⚠️ Aucun ledger trouvé. Abandon."
    exit 0
}

$lines = Get-Content $ledgerPath -Encoding UTF8
if (-not $lines -or $lines.Count -eq 0) {
    Write-Warning "⚠️ Ledger vide. Abandon."
    exit 0
}

Write-Host "→ Ledger : $ledgerPath ($($lines.Count) entrées)"

function Get-Sha256Hex([byte[]]$data) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($data)
    return (($hash | ForEach-Object ToString x2) -join '').ToLower()
}

# 2) niveau 0 = feuilles
$layers = @()   # tableau de niveaux, layers[0] = feuilles
$leaves = @()
foreach ($line in $lines) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($line)
    $leaves += (Get-Sha256Hex $bytes)
}
$layers += ,$leaves  # ajoute comme premier niveau

# 3) construire tous les niveaux pour récupérer les siblings ensuite
$curr = $leaves
while ($curr.Count -gt 1) {
    $next = @()
    for ($i = 0; $i -lt $curr.Count; $i += 2) {
        $left = $curr[$i]
        $right = $null
        if ($i + 1 -lt $curr.Count) {
            $right = $curr[$i + 1]
        } else {
            $right = $left   # duplication si impair
        }
        $concat = [Text.Encoding]::UTF8.GetBytes($left + $right)
        $parent = Get-Sha256Hex $concat
        $next += $parent
    }
    $layers += ,$next
    $curr = $next
}

$root = $layers[-1][0]
Write-Host "✅ Merkle root : $root"

# 4) générer les proofs
New-Item -ItemType Directory -Force -Path "out/proofs" | Out-Null

$proofsIndex = @()

for ($i = 0; $i -lt $lines.Count; $i++) {
    $proof = @()
    $idx = $i
    # on part du niveau 0 (feuilles) jusqu'au dernier - 1
    for ($level = 0; $level -lt $layers.Count - 1; $level++) {
        $layer = $layers[$level]
        $isLast = ($idx -eq $layer.Count - 1)
        $isOddCount = ($layer.Count % 2 -ne 0)

        # position paire → sibling = idx + 1
        if ($idx % 2 -eq 0) {
            if ($idx + 1 -lt $layer.Count) {
                $sibling = $layer[$idx + 1]
            } else {
                # si on est le dernier d'un niveau impair -> sibling = soi-même
                $sibling = $layer[$idx]
            }
            $proof += @{ dir = "right"; hash = $sibling }
        } else {
            # position impaire → sibling = idx - 1
            $sibling = $layer[$idx - 1]
            $proof += @{ dir = "left"; hash = $sibling }
        }

        # pour monter d'un niveau : idx // 2
        $idx = [int][math]::Floor($idx / 2)
    }

    $entry = [ordered]@{
        index     = $i
        timestamp = (Get-Date).ToString("s")
        ledger    = $ledgerPath
        line      = $lines[$i]
        leafHash  = $leaves[$i]
        merkleRoot = $root
        proof     = $proof
    }

    $outFile = "out/proofs/{0:D5}.json" -f $i
    ($entry | ConvertTo-Json -Depth 10) | Set-Content -Path $outFile -Encoding UTF8

    $proofsIndex += @{
        index = $i
        file  = $outFile
        leaf  = $leaves[$i]
    }
}

# 5) écrire un index global
$indexObj = [ordered]@{
    project    = "HUMEAN"
    version    = "v1.3"
    timestamp  = (Get-Date).ToString("s")
    ledger     = $ledgerPath
    merkleRoot = $root
    count      = $lines.Count
    proofs     = $proofsIndex
}
($indexObj | ConvertTo-Json -Depth 10) | Set-Content -Path "out/proofs-index.json" -Encoding UTF8

Write-Host "✅ proofs générées dans out/proofs/ et index dans out/proofs-index.json"
Write-Host "=== FIN HUMEAN | build merkle proofs ==="
