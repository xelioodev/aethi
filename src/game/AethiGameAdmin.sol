// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {AethiGameState} from "./AethiGameState.sol";
import {IAethiItems} from "../interfaces/IAethiItems.sol";

/// @title AethiGameAdmin
/// @notice Admin controls for Aethi game configuration and emergency pause.
abstract contract AethiGameAdmin is AethiGameState {
    function setGameConfig(
        address treasury_,
        uint256 minStakeToPlay_,
        uint256 entryFee_,
        uint256 stakeBoostCapBps_,
        uint256 maxSeasonRound_,
        uint256 actionTimeout_,
        uint256 claimPeriod_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (treasury_ == address(0)) {
            revert ZeroAddress();
        }
        _validateGameConfig(stakeBoostCapBps_, maxSeasonRound_, actionTimeout_, claimPeriod_);

        treasury = treasury_;
        minStakeToPlay = minStakeToPlay_;
        entryFee = entryFee_;
        stakeBoostCapBps = stakeBoostCapBps_;
        maxSeasonRound = maxSeasonRound_;
        actionTimeout = actionTimeout_;
        claimPeriod = claimPeriod_;

        emit GameConfigUpdated(treasury_, minStakeToPlay_, entryFee_, stakeBoostCapBps_);
    }

    function setItemCollection(IAethiItems itemCollection_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(itemCollection_) == address(0)) {
            revert ZeroAddress();
        }

        itemCollection = itemCollection_;
        emit ItemCollectionUpdated(address(itemCollection_));
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
