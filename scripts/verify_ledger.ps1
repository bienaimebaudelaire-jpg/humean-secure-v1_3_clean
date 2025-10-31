Param(
  [string]$LedgerPath = "attestation/ledger.log",
  [string]$SigPath    = "attestation/ledger.sshsig",
  [string]$Signers    = "attestation/keys/allowed_signers"
)
cmd /c "type ""$LedgerPath"" | ssh-keygen -Y verify -f ""$Signers"" -I humean -n file -s ""$SigPath"""
