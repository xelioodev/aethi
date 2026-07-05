// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title AethiBattleMath
/// @notice Pure scoring helpers for Aethi battle seasons.
library AethiBattleMath {
    error InvalidAction();

    function battleScore(uint256 baseScore, uint8 action, bool wonBattle, uint256 streak)
        internal
        pure
        returns (uint256)
    {
        uint256 actionBps;
        if (action == 1) {
            actionBps = wonBattle ? 2_000 : 0;
        } else if (action == 2) {
            actionBps = wonBattle ? 1_000 : 500;
        } else if (action == 3) {
            actionBps = wonBattle ? 500 : 0;
        } else {
            revert InvalidAction();
        }

        uint256 streakBps = streak > 5 ? 1_000 : streak * 200;
        return applyBoost(baseScore, actionBps + streakBps);
    }

    function stakeBoostBps(uint256 stakeSnapshot, uint256 minimum, uint256 capBps) internal pure returns (uint256) {
        if (minimum == 0 || stakeSnapshot <= minimum) {
            return 0;
        }

        uint256 excessRatioBps = ((stakeSnapshot - minimum) * 10_000) / minimum;
        uint256 boostBps = excessRatioBps <= 10_000 ? excessRatioBps / 2 : 5_000 + ((excessRatioBps - 10_000) / 4);
        return boostBps > capBps ? capBps : boostBps;
    }

    function applyBoost(uint256 amount, uint256 boostBps) internal pure returns (uint256) {
        return (amount * (10_000 + boostBps)) / 10_000;
    }
}
