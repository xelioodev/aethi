# Roadmap

The roadmap is ordered by protocol maturity rather than marketing milestones.

## Current

- Capped AETHI token
- Signed item minting
- Staking with reward periods and unstake cooldown
- Season creation with escrowed reward pools
- Stake snapshots and capped score boosts
- Battle action commits and operator-resolved rounds
- Signed battle result attestations
- Batch battle resolution
- Round expiry for stale committed actions
- Season cancellation
- Claim-window dust sweep
- Action, streak, stake, and item score modifiers
- Item classes, action affinity, and charges
- Pro-rata season reward claims

## Next

- Match queues and bracket metadata
- Invariant tests for reward conservation and stake accounting
- Event indexing schema for seasons, participants, and claims
- Replay monitoring for signed battle attestations
- Operator dashboard for pending action expiry

## Later

- Dispute window before finalization
- Merkle or aggregate proof support for offchain match results
- PvP ladders with matchmaking buckets
- Item durability, rarity classes, or season-scoped item rules
- Governance-controlled parameter updates
- Dedicated treasury and emissions policy

## Mainnet Readiness

- Independent audit
- Static analysis in CI
- Multisig ownership for admin roles
- Monitoring for role changes, season creation, score recording, and reward claims
- Documented incident response for signer or operator compromise
