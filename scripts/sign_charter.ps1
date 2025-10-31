param(
    [Parameter(Mandatory=$true)] [string]$CharterPath,
    [Parameter(Mandatory=$true)] [string]$PrivKeyPath,
    [Parameter(Mandatory=$true)] [string]$OutLedger
)

Write-Host "=== HUMEAN | SIGN CHARTER (with fallback) ==="

if (-not (Test-Path $CharterPath)) {
    Write-Error "❌ Charter introuvable : $CharterPath"
    exit 1
}
if (-not (Test-Path $PrivKeyPath)) {
    Write-Error "❌ Clé privée introuvable : $PrivKeyPath"
    exit 1
}

# 1) lire le charter
$charterData = Get-Content $CharterPath -Raw -Encoding UTF8

# 2) hash SHA256 du charter
$sha = [System.Security.Cryptography.SHA256]::Create()
$charterHashBytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($charterData))
$charterHashHex = ($charterHashBytes | ForEach-Object ToString x2) -join ''

# 3) essayer ED25519 .NET
$signatureB64 = $null
$used = $null

try {
    $privKeyRaw = Get-Content $PrivKeyPath -Raw

    # si le fichier est déjà en b64 (cas GitHub)
    try {
        $privKeyBytes = [Convert]::FromBase64String($privKeyRaw.Trim())
    } catch {
        # sinon on suppose binaire
        $privKeyBytes = [IO.File]::ReadAllBytes($PrivKeyPath)
    }

    # .NET 8+
    $sig = [System.Security.Cryptography.Ed25519]::Sign($charterHashBytes, $privKeyBytes)
    $signatureB64 = [Convert]::ToBase64String($sig)
    $used = "ed25519-dotnet"
    Write-Host "✅ Signature ED25519 .NET réussie."
}
catch {
    Write-Warning "⚠️ ED25519 .NET indisponible ou clé incompatible, tentative OpenSSL..."
}

# 4) fallback OpenSSL si pas de signature
if (-not $signatureB64) {
    # On va signer le contenu brut (pas seulement le hash) pour rester simple côté OpenSSL
    $tmpData = "humean_data_to_sign.bin"
    $tmpSig  = "humean_data_to_sign.sig"
    [IO.File]::WriteAllBytes($tmpData, [Text.Encoding]::UTF8.GetBytes($charterData))

    $openssl = Get-Command openssl -ErrorAction SilentlyContinue
    if ($openssl) {
        # openssl pkeyutl -sign -inkey KEY -in FILE -out SIG
        $cmd = "openssl pkeyutl -sign -inkey `"$PrivKeyPath`" -in `"$tmpData`" -out `"$tmpSig`""
        Write-Host "→ $cmd"
        cmd /c $cmd | Out-Null

        if (Test-Path $tmpSig) {
            $sigBytes = [IO.File]::ReadAllBytes($tmpSig)
            $signatureB64 = [Convert]::ToBase64String($sigBytes)
            $used = "openssl-pkeyutl"
            Write-Host "✅ Signature OpenSSL réussie."
            Remove-Item $tmpSig -Force
        } else {
            Write-Warning "⚠️ OpenSSL n'a pas produit de signature."
        }

        Remove-Item $tmpData -Force
    } else {
        Write-Warning "⚠️ OpenSSL non présent sur le système, impossible de faire le fallback."
    }
}

if (-not $signatureB64) {
    Write-Warning "⚠️ Aucune signature possible, on écrit quand même le ledger avec <no-signature>."
    $signatureB64 = "<no-signature>"
    $used = "none"
}

# 5) écrire une entrée dans le ledger
$entry = [ordered]@{
    timestamp = (Get-Date).ToString("s")
    charter   = (Split-Path $CharterPath -Leaf)
    hash      = $charterHashHex
    signature = $signatureB64
    method    = $used
}

$entryJson = $entry | ConvertTo-Json -Compress
New-Item -ItemType Directory -Force -Path (Split-Path $OutLedger) | Out-Null
Add-Content -Path $OutLedger -Value $entryJson

Write-Host "✅ Charter signé → $OutLedger"
Write-Host "=== FIN HUMEAN SIGN ==="
