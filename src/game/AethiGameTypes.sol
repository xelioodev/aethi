// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title AethiGameTypes
/// @notice Shared data types for Aethi battle seasons.
library AethiGameTypes {
    enum BattleAction {
        None,
        Strike,
        Guard,
        Focus
    }

    struct Season {
        uint64 startTime;
        uint64 endTime;
        uint256 rewardPool;
        uint256 totalScore;
        uint256 claimedRewards;
        uint256 minStakeToPlay;
        uint256 entryFee;
        uint256 stakeBoostCapBps;
        uint256 maxRound;
        uint256 actionTimeout;
        uint256 claimDeadline;
        uint256 participantCount;
        address treasury;
        bool finalized;
        bool cancelled;
        bool dustSwept;
    }

    struct BattleResult {
        uint256 seasonId;
        address player;
        uint256 round;
        uint256 baseScore;
        bool wonBattle;
        uint256 deadline;
    }
}
