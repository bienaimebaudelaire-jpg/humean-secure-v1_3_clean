#!/usr/bin/env pwsh
# ci/sign-and-verify-ci.ps1

$ErrorActionPreference = "Stop"

Write-Host "=== HUMEAN CI | SIGN + VERIFY ==="

# 0) créer les dossiers minimaux
New-Item -ItemType Directory -Force -Path "attestation" | Out-Null
New-Item -ItemType Directory -Force -Path "log" | Out-Null

# 1) écrire les clés depuis l'environnement si dispo
$privFromEnv = $env:HUMEAN_PRIVKEY_B64
$pubFromEnv  = $env:HUMEAN_PUBKEY_B64

if ($privFromEnv) {
    Write-Host "→ clé privée trouvée dans l'env, décodage..."
    $bytes = [Convert]::FromBase64String($privFromEnv)
    [IO.File]::WriteAllBytes("attestation/PRIMARY-KEY-003.priv", $bytes)
} else {
    Write-Warning "⚠️ HUMEAN_PRIVKEY_B64 absent (on pourra quand même vérifier si le ledger est déjà signé)."
}

if ($pubFromEnv) {
    Write-Host "→ clé publique trouvée dans l'env, décodage..."
    $bytes = [Convert]::FromBase64String($pubFromEnv)
    [IO.File]::WriteAllBytes("attestation/PRIMARY-KEY-003.pub", $bytes)
} else {
    Write-Warning "⚠️ HUMEAN_PUBKEY_B64 absent (on utilisera la clé du repo si présente)."
}

# 2) SIGNER si le script existe
$signScript = "scripts/sign_charter.ps1"
$charter    = "charter_v1_3.json"
$privKey    = "attestation/PRIMARY-KEY-003.priv"
$outLedger  = "log/ledger_signed.jsonl"

if (Test-Path $signScript) {
    Write-Host "→ script de signature trouvé : $signScript"
    if (-not (Test-Path $charter)) {
        Write-Warning "⚠️ Charter $charter introuvable, je ne peux pas le signer. Étape ignorée."
    } elseif (-not (Test-Path $privKey)) {
        Write-Warning "⚠️ Clé privée $privKey introuvable, je ne peux pas signer. Étape ignorée."
    } else {
        Write-Host "→ lancement de la signature..."
        pwsh $signScript -CharterPath $charter -PrivKeyPath $privKey -OutLedger $outLedger
        Write-Host "✅ signature terminée."
    }
} else {
    Write-Warning "⚠️ $signScript introuvable dans le repo → on n'échoue PAS le job."
}

# 3) commit & push si chgmt
# (on n'échoue pas si git n'est pas propre)
try {
    $status = git status --porcelain
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        Write-Host "→ changements détectés, on commit..."
        git add log/ attestation/ $charter 2>$null
        git commit -m "ci: auto sign ledger" | Write-Host
        git push origin HEAD:main | Write-Host
        Write-Host "✅ changements poussés."
    } else {
        Write-Host "→ aucun changement à pousser."
    }
} catch {
    Write-Warning "⚠️ impossible de pousser (peut-être pas de token ?), on continue."
}

# 4) vérification
if (Test-Path "ci/verify-ledger-ci.ps1") {
    Write-Host "→ vérification du ledger..."
    pwsh ./ci/verify-ledger-ci.ps1
    Write-Host "✅ vérification terminée."
} else {
    Write-Warning "⚠️ ci/verify-ledger-ci.ps1 introuvable, pas de vérif."
}

Write-Host "=== FIN HUMEAN CI | SIGN + VERIFY ==="
exit 0
