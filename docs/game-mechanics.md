# Game Mechanics

Aethi seasons are built around committed battle actions and signed match results.

## Season Entry

Players must stake at least the season minimum before joining. On join, the game snapshots the player's stake and the season parameters. That snapshot is used until the season ends.

## Battle Rounds

Each round follows this path:

```text
player commits action -> operator signs result -> result is submitted -> score is updated
```

Actions:

| Action | Win behavior | Loss behavior |
| --- | --- | --- |
| Strike | Highest win bonus. | No action bonus. |
| Guard | Moderate win bonus. | Small loss protection. |
| Focus | Small win bonus. | No action bonus. |

Committed actions expire after the season's action timeout. Expired actions can be cleared and replaced by a later round.

## Score Formula

```text
actionScore = baseScore + action bonus + streak bonus
seasonScore = actionScore + stake boost + matching item boost
```

Stake boost uses diminishing returns and is capped per season. Item boost applies only when the equipped item still belongs to the player, has remaining charges, and matches the battle action affinity. Affinity `0` means the item can support any action.

## Items

Items carry:

- item type
- item class
- action affinity
- boost power
- battle charges
- metadata URI

Minting requires a typed signature from an item signer. Battle resolution consumes one charge when an equipped item contributes its boost.

## Match Results

Operators do not freely write arbitrary score. They sign an EIP-712 battle result containing:

- season id
- player
- round
- base score
- win/loss result
- deadline

The submitted result must match the player's pending committed round.
