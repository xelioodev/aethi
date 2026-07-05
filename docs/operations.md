# Operations

This document covers live protocol operation.

## Roles

Use separate accounts for:

- admin
- item signer
- game operator
- season manager
- reward manager
- distributor
- pauser

Admin roles should be controlled by a multisig. Hot operational keys should only hold narrow roles.

## Season Runbook

1. Fund the season reward pool.
2. Create the season with start and end timestamps.
3. Monitor joins and committed actions.
4. Sign battle results offchain.
5. Submit results individually or in batches.
6. Finalize after season end.
7. Monitor claims through the claim window.
8. Sweep dust after the claim window closes.

## Incident Handling

If an item signer is compromised:

- revoke `ITEM_SIGNER_ROLE`
- rotate signer
- monitor unusual item mints

If a game operator is compromised:

- revoke `GAME_OPERATOR_ROLE`
- pause game actions if needed
- review signed battle results and pending submissions

If a season is malformed before meaningful score is recorded:

- cancel the season
- refund the reward pool to the selected recipient

## Monitoring

Track:

- role changes
- item mints
- season creation and cancellation
- battle action commits
- battle resolutions
- season finalization
- claims and dust sweeps
