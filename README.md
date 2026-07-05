<p align="center">
  <img src="docs/assets/aethi-banner.svg" alt="aethi" width="100%" />
</p>

# aethi

Aethi is a compact onchain game protocol for seasonal play.

Players stake AETHI, mint signed item NFTs, join live seasons, commit battle actions, earn resolved score, and claim rewards from season pools. The contracts keep token supply, item ownership, staking access, game state, and auxiliary rewards separated.

## Contracts

| Contract | Purpose |
| --- | --- |
| `AethiToken` | Capped ERC20 with permit, pausing, and role-gated minting. |
| `AethiItems` | ERC721 item collection with EIP-712 mint authorizations. |
| `AethiStaking` | Single-token staking vault with reward periods, reward-per-share accounting, and unstake cooldown. |
| `AethiGame` | Season lifecycle, entry checks, stake snapshots, battle actions, item boosts, score resolution, and reward claims. |
| `AethiRewardDistributor` | Controlled vault for direct reward distributions. |

## Flow

```text
stake AETHI -> mint signed item -> join season -> equip item -> commit action -> resolve battle -> claim rewards
```

## Design

- Token and item logic use audited OpenZeppelin Contracts primitives.
- Item minting uses typed signatures, account nonces, deadlines, and capped boost power.
- Staking rewards use accumulated reward-per-share accounting and do not iterate over users.
- Season parameters and player stake are snapshotted so active seasons are not changed by later config updates.
- Battle rounds require player action commits and signed match results before resolution.
- Items can carry classes, action affinity, finite charges, and bounded boost power.
- Season rewards are escrowed when a season is created and paid pro-rata after finalization.
- Privileged actions are split across admin, signer, operator, season, reward, and pause roles.
- The game contract does not use block values for randomness.

## Layout

```text
src/
  game/
  interfaces/
  items/
  rewards/
  staking/
  token/

docs/
  architecture.md
  threat-model.md
```

## Deployment

Set the variables in `.env.example`, then run the deployment script for the target network. The script deploys the five core contracts and connects `AethiItems` to `AethiGame`.

## Documentation

- [Architecture](docs/architecture.md)
- [Game mechanics](docs/game-mechanics.md)
- [Economics](docs/economics.md)
- [Operations](docs/operations.md)
- [Threat model](docs/threat-model.md)
- [Roadmap](docs/roadmap.md)

## Assets

- [Logo mark](docs/assets/aethi-logo-mark.svg)
- [Wordmark](docs/assets/aethi-wordmark.svg)
- [Banner](docs/assets/aethi-banner.svg)
- [Social preview](docs/assets/aethi-social-preview.svg)

## Status

Experimental. Review roles, monitoring, invariant tests, and independent audit coverage before production use.
