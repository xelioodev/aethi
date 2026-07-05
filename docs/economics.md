# Economics

The token economy is intentionally narrow.

## Token Uses

AETHI is used for:

- staking access
- season entry fees
- season reward pools
- staking emissions
- direct reward distributions

## Supply

`AethiToken` has an immutable cap. Minting is role-gated and cannot exceed that cap.

## Season Pools

Season rewards are escrowed when a season is created. After finalization, players claim pro-rata by season score:

```text
reward = rewardPool * playerScore / totalSeasonScore
```

Integer division can leave dust. After the claim window closes, season managers can sweep unclaimed or rounding dust to a configured recipient.

## Staking

Staking has two jobs:

- qualify players for season entry
- pay time-based rewards

Reward accounting uses accumulated reward per share and does not loop through stakers. Unstake cooldown makes stake commitments meaningful for active game participation.

## Boost Balance

Stake boost uses diminishing returns. Items use finite charges. Both are capped so score cannot scale without bounds.
