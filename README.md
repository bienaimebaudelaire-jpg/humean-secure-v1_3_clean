# HUMEAN - You Mean. We Mean. To Be Human.

HUMEAN = IA x Humanite with verifiable guarantees (charters, policies, attestations).

Local verify:
    cat attestation/ledger.log | ssh-keygen -Y verify -f attestation/keys/pub_ed25519.openssh -I humean -n file -s attestation/ledger.sshsig

License: AGPL-3.0
