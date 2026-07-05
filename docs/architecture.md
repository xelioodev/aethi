# Aethi Architecture

Aethi separates the game economy into small contracts with clear ownership boundaries: token supply, item issuance, staking, season state, and direct reward operations.

## Core Model

Players stake AETHI before entering a season. When a player joins, the game snapshots their current stake and the season's economic settings. That snapshot is used for the whole season, so later admin configuration changes do not alter active season rules.

Each round has a small battle loop:

1. the player commits an action: strike, guard, or focus
2. the operator signs a match result containing the base score
3. the contract applies action, streak, stake, and item modifiers
4. the resulting score is added to the season total

The final recorded score can include bounded modifiers:

- action bonus based on the committed battle action
- win streak bonus capped after five wins
- stake boost, derived from stake above the season minimum and capped per season
- item boost, derived from one equipped charged item NFT

The game contract does not use block values for randomness.

```text
base match score
  + battle action modifier
  + win streak modifier
  + stake snapshot modifier
  + equipped item modifier
  = season score
```

## Contracts

### AethiToken

Capped ERC20 used for staking, entry fees, rewards, and operational distributions. Minting and pausing are role-gated.

### AethiItems

ERC721 item collection. Item mints require EIP-712 authorization from an item signer. Each authorization binds the player, item type, item class, action affinity, boost value, charges, metadata hash, nonce, and deadline.

### AethiStaking

Single-token staking vault with reward-per-share accounting. It supports:

- time-based reward periods
- no iteration over stakers
- claimable reward checkpoints
- configurable unstake cooldown
- emergency withdrawal after cooldown

The cooldown makes stake commitments meaningful for season access while keeping withdrawals deterministic.

### AethiGame

Season coordinator. It handles:

- season creation with escrowed rewards
- per-season snapshots for minimum stake, entry fee, treasury, and stake boost cap
- participant stake snapshots at join time
- item equip checks
- battle action commitments
- signed battle result verification
- batch battle resolution
- action expiry
- action and streak modifiers
- boosted score accounting
- season cancellation
- finalization and pro-rata reward claims
- dust sweep after claim window

### AethiRewardDistributor

Controlled vault for direct rewards outside season pools.

## State Flow

```text
AethiToken
  -> staked in AethiStaking
  -> paid as AethiGame entry fees
  -> escrowed as season reward pools
  -> distributed by AethiRewardDistributor

AethiItems
  -> minted with signed authorization
  -> equipped in AethiGame
  -> read during battle resolution

AethiStaking
  -> exposes stakedBalanceOf(account)
  -> read by AethiGame when a player joins
```

## Roles

| Role | Contract | Capability |
| --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | all role-based contracts | Grants and revokes roles. |
| `MINTER_ROLE` | `AethiToken` | Mints AETHI up to the cap. |
| `PAUSER_ROLE` | token, items, staking, game, distributor | Pauses sensitive operations. |
| `ITEM_SIGNER_ROLE` | `AethiItems` | Signs item mint authorizations. |
| `METADATA_MANAGER_ROLE` | `AethiItems` | Updates item metadata URI. |
| `REWARD_MANAGER_ROLE` | `AethiStaking` | Funds reward periods and configures staking parameters. |
| `SEASON_MANAGER_ROLE` | `AethiGame` | Creates and finalizes seasons. |
| `GAME_OPERATOR_ROLE` | `AethiGame` | Records player score. |
| `DISTRIBUTOR_ROLE` | `AethiRewardDistributor` | Sends funded direct rewards. |

## Invariants To Preserve

- Season reward pools are escrowed before a season is announced.
- A participant's stake snapshot never changes after joining a season.
- Admin config changes only affect future seasons.
- Item boosts cannot be used after the equipped item leaves the player wallet.
- A resolved battle must correspond to a player-committed round action.
- A battle result must be signed by an account with `GAME_OPERATOR_ROLE`.
- Battle streaks reset on a loss.
- Item charges decrease when an item contributes its boost.
- Staking reward accounting must update before any change to total staked principal.
- No user-facing loop should depend on the number of players or stakers.
