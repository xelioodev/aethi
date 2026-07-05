# Aethi Threat Model

This document describes the main risks and trust assumptions for the Aethi smart contract system.

## Scope

In scope:

- AETHI ERC20 token
- Aethi item NFTs
- staking vault
- season gameplay
- reward distributor
- role and signer permissions

Out of scope:

- web application security
- backend infrastructure
- private key custody systems
- indexers
- bridges
- marketplaces
- off-chain anti-cheat logic

## Protected Assets

- AETHI token supply
- user staked principal
- funded staking rewards
- escrowed season reward pools
- item NFT ownership
- item mint signing authority
- score recording authority
- admin roles

## Trust Assumptions

Aethi uses explicit privileged roles. These roles should be assigned carefully, ideally to multisigs or dedicated operational signers.

| Actor | Trust Required |
| --- | --- |
| Admin | Can grant and revoke protocol roles. |
| Item signer | Can authorize NFT item mints. |
| Game operator | Can sign battle result attestations. |
| Season manager | Can create and finalize seasons. |
| Reward manager | Can fund staking reward periods. |
| Distributor | Can send funded bonus rewards. |

## Key Risks

### Admin Compromise

A compromised admin can grant roles to malicious accounts.

Mitigations:

- assign admin roles to a multisig
- separate cold admin roles from hot operational roles
- monitor role events
- use conservative role assignment procedures

### Item Signer Compromise

A compromised item signer can authorize unwanted NFT mints.

Mitigations:

- item mint signatures include player-specific nonces
- signatures include deadlines
- item power is capped
- signer role can be revoked
- signing keys can be rotated

### Game Operator Misbehavior

The current game model trusts operators to sign accurate battle results.

Mitigations:

- score updates are emitted as events
- battle results are EIP-712 typed attestations
- submitted results must match a committed player action and round
- attestations include deadlines
- operator role is separate from admin
- future versions can add signed score attestations, oracle-backed results, dispute windows, or verifiable game proofs

### Item Boost Abuse

Items can affect battle score.

Mitigations:

- item power is capped
- item boosts only apply when the item is still owned by the player
- action affinity limits which actions can receive a boost
- battle charges are consumed when an item contributes

### Reward Accounting Errors

Incorrect accounting could overpay or underpay users.

Mitigations:

- staking uses accumulated reward-per-share accounting
- reward operations do not loop over all users
- reward periods are explicitly funded
- tests cover staking, unstaking, claiming, and reward accrual
- season dust can be swept only after the claim window closes

### Timestamp Sensitivity

The protocol uses timestamps for season windows, reward periods, and signature deadlines.

Mitigations:

- timestamps are not used for randomness
- season and reward periods are coarse-grained
- deadline checks are used only for authorization freshness

### Reentrancy

Token transfers and reward claims involve external calls.

Mitigations:

- token-moving flows use `nonReentrant`
- ERC20 transfers use `SafeERC20`
- state is updated before external reward transfers where applicable

## Recommended Production Checklist

- Assign admin roles to a multisig.
- Use separate keys for signing, operation, and administration.
- Add invariant tests for staking principal and reward conservation.
- Add static analysis to CI.
- Define signer rotation and incident response procedures.
- Monitor role changes, season creation, score updates, and reward claims.
- Complete an independent audit before mainnet deployment.
