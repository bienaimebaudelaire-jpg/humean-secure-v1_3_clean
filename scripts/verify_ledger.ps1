Param([string]$LedgerPath="attestation/ledger.log",[string]$SigPath="attestation/ledger.sshsig",[string]$PubKeyPath="attestation/keys/pub_ed25519.openssh")
Get-Content $LedgerPath | ssh-keygen -Y verify -f $PubKeyPath -I "humean" -n file -s $SigPath
