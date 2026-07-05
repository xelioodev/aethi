// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {AethiGameAdmin} from "./AethiGameAdmin.sol";
import {AethiBattleMath} from "./AethiBattleMath.sol";
import {AethiGameState} from "./AethiGameState.sol";
import {AethiGameTypes} from "./AethiGameTypes.sol";
import {IAethiStaking} from "../interfaces/IAethiStaking.sol";

/// @title AethiGame
/// @notice Season coordinator for stake-gated battle rounds and reward pools.
/// @dev Match outcomes are signed attestations; the contract does not derive randomness from block values.
contract AethiGame is AethiGameAdmin {
    using SafeERC20 for IERC20;

    constructor(
        IERC20 token_,
        IAethiStaking staking_,
        address treasury_,
        address admin,
        uint256 minStakeToPlay_,
        uint256 entryFee_,
        uint256 stakeBoostCapBps_,
        uint256 maxSeasonRound_,
        uint256 actionTimeout_,
        uint256 claimPeriod_
    )
        AethiGameState(
            token_,
            staking_,
            treasury_,
            admin,
            minStakeToPlay_,
            entryFee_,
            stakeBoostCapBps_,
            maxSeasonRound_,
            actionTimeout_,
            claimPeriod_
        )
    {}

    function createSeason(uint64 startTime, uint64 endTime, uint256 rewardPool)
        external
        nonReentrant
        onlyRole(SEASON_MANAGER_ROLE)
        returns (uint256 seasonId)
    {
        if (startTime >= endTime || endTime <= block.timestamp || rewardPool == 0) {
            revert InvalidSeason();
        }

        uint256 seasonClaimDeadline = uint256(endTime) + claimPeriod;
        seasonId = nextSeasonId++;
        seasons[seasonId] = AethiGameTypes.Season({
            startTime: startTime,
            endTime: endTime,
            rewardPool: rewardPool,
            totalScore: 0,
            claimedRewards: 0,
            minStakeToPlay: minStakeToPlay,
            entryFee: entryFee,
            stakeBoostCapBps: stakeBoostCapBps,
            maxRound: maxSeasonRound,
            actionTimeout: actionTimeout,
            claimDeadline: seasonClaimDeadline,
            participantCount: 0,
            treasury: treasury,
            finalized: false,
            cancelled: false,
            dustSwept: false
        });

        token.safeTransferFrom(msg.sender, address(this), rewardPool);
        emit SeasonCreated(seasonId, startTime, endTime, rewardPool, seasonClaimDeadline);
    }

    function cancelSeason(uint256 seasonId, address recipient) external nonReentrant onlyRole(SEASON_MANAGER_ROLE) {
        AethiGameTypes.Season storage season = seasons[seasonId];
        if (recipient == address(0)) {
            revert ZeroAddress();
        }
        if (season.endTime == 0 || season.finalized || season.cancelled) {
            revert InvalidSeason();
        }
        if (block.timestamp >= season.startTime) {
            revert SeasonActive();
        }

        season.cancelled = true;
        uint256 refund = season.rewardPool - season.claimedRewards;
        season.claimedRewards = season.rewardPool;
        token.safeTransfer(recipient, refund);

        emit SeasonCancelled(seasonId, recipient, refund);
    }

    function joinSeason(uint256 seasonId) external nonReentrant whenNotPaused {
        AethiGameTypes.Season memory season = seasons[seasonId];
        if (!_isActive(season)) {
            revert SeasonClosed();
        }
        if (hasJoined[seasonId][msg.sender]) {
            revert AlreadyJoined();
        }

        uint256 stakeSnapshot = staking.stakedBalanceOf(msg.sender);
        if (stakeSnapshot < season.minStakeToPlay) {
            revert TooLittleStake();
        }

        hasJoined[seasonId][msg.sender] = true;
        stakeSnapshots[seasonId][msg.sender] = stakeSnapshot;
        seasons[seasonId].participantCount += 1;

        if (season.entryFee != 0) {
            token.safeTransferFrom(msg.sender, season.treasury, season.entryFee);
        }

        emit SeasonJoined(seasonId, msg.sender, stakeSnapshot);
    }

    function equipItem(uint256 seasonId, uint256 tokenId) external whenNotPaused {
        AethiGameTypes.Season memory season = seasons[seasonId];
        if (!_isActive(season)) {
            revert SeasonClosed();
        }
        if (!hasJoined[seasonId][msg.sender]) {
            revert InvalidSeason();
        }
        if (address(itemCollection) == address(0)) {
            revert ZeroAddress();
        }
        if (itemCollection.ownerOf(tokenId) != msg.sender) {
            revert InvalidSeason();
        }
        if (itemCollection.itemCharges(tokenId) == 0) {
            revert NoItemCharges();
        }

        uint256 powerBps = itemCollection.itemPower(tokenId);
        equippedItems[seasonId][msg.sender] = tokenId;

        emit ItemEquipped(seasonId, msg.sender, tokenId, powerBps);
    }

    function commitBattleAction(uint256 seasonId, uint256 round, AethiGameTypes.BattleAction action)
        external
        whenNotPaused
    {
        AethiGameTypes.Season memory season = seasons[seasonId];
        if (!_isActive(season)) {
            revert SeasonClosed();
        }
        if (!hasJoined[seasonId][msg.sender]) {
            revert InvalidSeason();
        }
        if (round == 0 || round > MAX_ACTION_ROUND || round > season.maxRound) {
            revert InvalidRound();
        }
        if (round <= pendingActionRounds[seasonId][msg.sender]) {
            revert InvalidRound();
        }
        if (action == AethiGameTypes.BattleAction.None) {
            revert InvalidAction();
        }
        if (
            pendingActions[seasonId][msg.sender] != AethiGameTypes.BattleAction.None
                && block.timestamp <= pendingActionDeadlines[seasonId][msg.sender]
        ) {
            revert PendingAction();
        }

        uint256 actionDeadline = block.timestamp + season.actionTimeout;
        pendingActions[seasonId][msg.sender] = action;
        pendingActionRounds[seasonId][msg.sender] = round;
        pendingActionDeadlines[seasonId][msg.sender] = actionDeadline;

        emit BattleActionCommitted(seasonId, msg.sender, round, action, actionDeadline);
    }

    function clearExpiredAction(uint256 seasonId, address player) external {
        AethiGameTypes.BattleAction action = pendingActions[seasonId][player];
        if (action == AethiGameTypes.BattleAction.None) {
            revert NoPendingAction();
        }
        if (block.timestamp <= pendingActionDeadlines[seasonId][player]) {
            revert PendingAction();
        }

        uint256 round = pendingActionRounds[seasonId][player];
        delete pendingActions[seasonId][player];
        delete pendingActionDeadlines[seasonId][player];

        emit BattleActionExpired(seasonId, player, round);
    }

    function resolveBattle(AethiGameTypes.BattleResult calldata result, bytes calldata signature)
        external
        whenNotPaused
    {
        _resolveBattle(result, signature);
    }

    function resolveBattles(AethiGameTypes.BattleResult[] calldata results, bytes[] calldata signatures)
        external
        whenNotPaused
    {
        if (results.length == 0 || results.length > MAX_BATCH_RESOLVE || results.length != signatures.length) {
            revert InvalidBatch();
        }

        for (uint256 i; i < results.length; ++i) {
            _resolveBattle(results[i], signatures[i]);
        }
    }

    function recordScore(uint256 seasonId, address player, uint256 scoreDelta)
        external
        whenNotPaused
        onlyRole(GAME_OPERATOR_ROLE)
    {
        AethiGameTypes.Season storage season = seasons[seasonId];
        if (!_isActive(season)) {
            revert SeasonClosed();
        }
        if (player == address(0)) {
            revert ZeroAddress();
        }
        if (!hasJoined[seasonId][player]) {
            revert InvalidSeason();
        }
        if (scoreDelta == 0) {
            revert InvalidAmount();
        }

        uint256 boostedScore = _scoreWithPassiveBoosts(seasonId, player, scoreDelta);
        scores[seasonId][player] += boostedScore;
        season.totalScore += boostedScore;

        emit ScoreRecorded(seasonId, player, boostedScore, scores[seasonId][player]);
    }

    function finalizeSeason(uint256 seasonId) external onlyRole(SEASON_MANAGER_ROLE) {
        AethiGameTypes.Season storage season = seasons[seasonId];
        if (season.endTime == 0) {
            revert InvalidSeason();
        }
        if (season.cancelled) {
            revert SeasonCancelledError();
        }
        if (season.finalized) {
            revert SeasonClosed();
        }
        if (block.timestamp < season.endTime) {
            revert SeasonActive();
        }

        season.finalized = true;
        emit SeasonFinalized(seasonId, season.totalScore, season.claimDeadline);
    }

    function claimSeasonReward(uint256 seasonId) external nonReentrant returns (uint256 reward) {
        AethiGameTypes.Season storage season = seasons[seasonId];
        if (!season.finalized) {
            revert SeasonNotFinalized();
        }
        if (season.cancelled) {
            revert SeasonCancelledError();
        }
        if (hasClaimed[seasonId][msg.sender]) {
            revert AlreadyClaimed();
        }

        hasClaimed[seasonId][msg.sender] = true;

        uint256 playerScore = scores[seasonId][msg.sender];
        if (playerScore == 0 || season.totalScore == 0) {
            return 0;
        }

        reward = (season.rewardPool * playerScore) / season.totalScore;
        season.claimedRewards += reward;
        token.safeTransfer(msg.sender, reward);

        emit SeasonRewardClaimed(seasonId, msg.sender, reward);
    }

    function sweepSeasonDust(uint256 seasonId, address recipient) external nonReentrant onlyRole(SEASON_MANAGER_ROLE) {
        AethiGameTypes.Season storage season = seasons[seasonId];
        if (recipient == address(0)) {
            revert ZeroAddress();
        }
        if (!season.finalized) {
            revert SeasonNotFinalized();
        }
        if (block.timestamp <= season.claimDeadline) {
            revert ClaimWindowActive();
        }
        if (season.dustSwept) {
            revert DustAlreadySwept();
        }

        season.dustSwept = true;
        uint256 dust = season.rewardPool - season.claimedRewards;
        season.claimedRewards = season.rewardPool;
        token.safeTransfer(recipient, dust);

        emit SeasonDustSwept(seasonId, recipient, dust);
    }

    function hashBattleResult(AethiGameTypes.BattleResult memory result) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    BATTLE_RESULT_TYPEHASH,
                    result.seasonId,
                    result.player,
                    result.round,
                    result.baseScore,
                    result.wonBattle,
                    result.deadline
                )
            )
        );
    }

    function _resolveBattle(AethiGameTypes.BattleResult calldata result, bytes calldata signature) internal {
        if (block.timestamp > result.deadline) {
            revert InvalidAttestation();
        }
        address signer = ECDSA.recoverCalldata(hashBattleResult(result), signature);
        if (!hasRole(GAME_OPERATOR_ROLE, signer)) {
            revert InvalidAttestation();
        }

        AethiGameTypes.Season memory season = seasons[result.seasonId];
        if (!_isActive(season)) {
            revert SeasonClosed();
        }
        if (result.player == address(0)) {
            revert ZeroAddress();
        }
        if (!hasJoined[result.seasonId][result.player]) {
            revert InvalidSeason();
        }
        if (result.baseScore == 0) {
            revert InvalidAmount();
        }
        if (pendingActionRounds[result.seasonId][result.player] != result.round) {
            revert InvalidRound();
        }
        if (resolvedBattles[result.seasonId][result.player][result.round]) {
            revert ResultAlreadyResolved();
        }
        if (block.timestamp > pendingActionDeadlines[result.seasonId][result.player]) {
            revert ActionExpired();
        }

        AethiGameTypes.BattleAction action = pendingActions[result.seasonId][result.player];
        if (action == AethiGameTypes.BattleAction.None) {
            revert NoPendingAction();
        }

        delete pendingActions[result.seasonId][result.player];
        delete pendingActionDeadlines[result.seasonId][result.player];
        resolvedBattles[result.seasonId][result.player][result.round] = true;
        _applyBattleResult(result, action);
    }

    function _applyBattleResult(AethiGameTypes.BattleResult calldata result, AethiGameTypes.BattleAction action)
        internal
    {
        uint256 streak = result.wonBattle ? winStreaks[result.seasonId][result.player] + 1 : 0;
        winStreaks[result.seasonId][result.player] = streak;

        uint256 actionScore = AethiBattleMath.battleScore(result.baseScore, uint8(action), result.wonBattle, streak);
        uint256 boostedScore = _scoreWithBattleBoosts(result.seasonId, result.player, actionScore, action);
        scores[result.seasonId][result.player] += boostedScore;
        seasons[result.seasonId].totalScore += boostedScore;

        emit BattleResolved(result.seasonId, result.player, result.round, action, actionScore, boostedScore, streak);
        emit ScoreRecorded(result.seasonId, result.player, boostedScore, scores[result.seasonId][result.player]);
    }

    function _scoreWithPassiveBoosts(uint256 seasonId, address player, uint256 baseScore)
        internal
        view
        returns (uint256)
    {
        uint256 tokenId = equippedItems[seasonId][player];
        uint256 boostBps = _stakeBoostBps(seasonId, player);
        if (tokenId != 0) {
            if (itemCollection.ownerOf(tokenId) != player) {
                revert InvalidItemOwner();
            }
            boostBps += itemCollection.itemPower(tokenId);
        }

        return AethiBattleMath.applyBoost(baseScore, boostBps);
    }

    function _scoreWithBattleBoosts(
        uint256 seasonId,
        address player,
        uint256 baseScore,
        AethiGameTypes.BattleAction action
    ) internal returns (uint256) {
        uint256 tokenId = equippedItems[seasonId][player];
        uint256 boostBps = _stakeBoostBps(seasonId, player);
        if (tokenId != 0) {
            if (itemCollection.ownerOf(tokenId) != player) {
                revert InvalidItemOwner();
            }

            uint8 affinity = itemCollection.actionAffinity(tokenId);
            if (affinity == 0 || affinity == uint8(action)) {
                boostBps += itemCollection.itemPower(tokenId);
                itemCollection.consumeItemCharge(tokenId);
            }
        }

        return AethiBattleMath.applyBoost(baseScore, boostBps);
    }

    function _stakeBoostBps(uint256 seasonId, address player) internal view returns (uint256) {
        AethiGameTypes.Season memory season = seasons[seasonId];
        uint256 minimum = season.minStakeToPlay;
        if (minimum == 0) {
            return 0;
        }

        uint256 stakeSnapshot = stakeSnapshots[seasonId][player];
        if (stakeSnapshot <= minimum) {
            return 0;
        }

        return AethiBattleMath.stakeBoostBps(stakeSnapshot, minimum, season.stakeBoostCapBps);
    }

    function _isActive(AethiGameTypes.Season memory season) internal view returns (bool) {
        return season.startTime <= block.timestamp && block.timestamp < season.endTime && !season.finalized
            && !season.cancelled;
    }
}
