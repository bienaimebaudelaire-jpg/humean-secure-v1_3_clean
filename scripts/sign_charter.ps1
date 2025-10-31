param(
    [Parameter(Mandatory=$true)] [string]$CharterPath,
    [Parameter(Mandatory=$true)] [string]$PrivKeyPath,
    [Parameter(Mandatory=$true)] [string]$OutLedger
)

Write-Host "=== HUMEAN | SIGN CHARTER ==="

if (-not (Test-Path $CharterPath)) {
    Write-Error "❌ Charter introuvable : $CharterPath"
    exit 1
}
if (-not (Test-Path $PrivKeyPath)) {
    Write-Error "❌ Clé privée introuvable : $PrivKeyPath"
    exit 1
}

# lecture des données
$charterJson = Get-Content $CharterPath -Raw
$charterHash = (echo $charterJson | openssl dgst -sha256 | ForEach-Object { $_.Split('=')[-1].Trim() })

# signature
$signature = & openssl dgst -sha256 -sign $PrivKeyPath -out temp.sig $CharterPath
$signatureB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("temp.sig"))
Remove-Item temp.sig -Force

# ledger append
$entry = @{
    timestamp = (Get-Date).ToString("s")
    charter   = $CharterPath
    hash      = $charterHash
    signature = $signatureB64
} | ConvertTo-Json -Compress

Add-Content -Path $OutLedger -Value $entry

Write-Host "✅ Charter signé et ajouté à $OutLedger"
Write-Host "=== FIN HUMEAN SIGN ==="
