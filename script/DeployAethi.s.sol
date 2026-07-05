// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Script} from "forge-std/Script.sol";

import {AethiGame} from "../src/game/AethiGame.sol";
import {AethiItems} from "../src/items/AethiItems.sol";
import {AethiRewardDistributor} from "../src/rewards/AethiRewardDistributor.sol";
import {AethiStaking} from "../src/staking/AethiStaking.sol";
import {AethiToken} from "../src/token/AethiToken.sol";

/// @title DeployAethi
/// @notice Deploys the Aethi token, item collection, staking vault, game coordinator, and reward distributor.
contract DeployAethi is Script {
    uint256 internal constant DEFAULT_INITIAL_SUPPLY = 100_000_000 ether;
    uint256 internal constant DEFAULT_SUPPLY_CAP = 1_000_000_000 ether;
    uint256 internal constant DEFAULT_REWARDS_DURATION = 30 days;
    uint256 internal constant DEFAULT_UNSTAKE_COOLDOWN = 1 days;
    uint256 internal constant DEFAULT_MIN_STAKE_TO_PLAY = 100 ether;
    uint256 internal constant DEFAULT_ENTRY_FEE = 1 ether;
    uint256 internal constant DEFAULT_STAKE_BOOST_CAP_BPS = 2_000;
    uint256 internal constant DEFAULT_MAX_SEASON_ROUND = 1_000;
    uint256 internal constant DEFAULT_ACTION_TIMEOUT = 15 minutes;
    uint256 internal constant DEFAULT_CLAIM_PERIOD = 7 days;

    struct DeployConfig {
        address admin;
        address treasury;
        address initialRecipient;
        uint256 initialSupply;
        uint256 supplyCap;
        uint256 rewardsDuration;
        uint256 unstakeCooldown;
        uint256 minStakeToPlay;
        uint256 entryFee;
        uint256 stakeBoostCapBps;
        uint256 maxSeasonRound;
        uint256 actionTimeout;
        uint256 claimPeriod;
    }

    /// @notice Deploys all core Aethi contracts.
    function run()
        external
        returns (
            AethiToken token,
            AethiItems items,
            AethiStaking staking,
            AethiGame game,
            AethiRewardDistributor rewardDistributor
        )
    {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        DeployConfig memory config = _loadConfig(deployerKey);

        vm.startBroadcast(deployerKey);

        token = new AethiToken(config.admin, config.initialRecipient, config.initialSupply, config.supplyCap);
        items = new AethiItems(config.admin);
        staking = new AethiStaking(token, token, config.admin, config.rewardsDuration, config.unstakeCooldown);
        game = new AethiGame(
            token,
            staking,
            config.treasury,
            config.admin,
            config.minStakeToPlay,
            config.entryFee,
            config.stakeBoostCapBps,
            config.maxSeasonRound,
            config.actionTimeout,
            config.claimPeriod
        );
        game.setItemCollection(items);
        items.grantRole(items.ITEM_CONSUMER_ROLE(), address(game));
        rewardDistributor = new AethiRewardDistributor(token, config.admin);

        vm.stopBroadcast();
    }

    function _loadConfig(uint256 deployerKey) internal view returns (DeployConfig memory config) {
        config.admin = vm.envOr("AETHI_ADMIN", vm.addr(deployerKey));
        config.treasury = vm.envOr("AETHI_TREASURY", config.admin);
        config.initialRecipient = vm.envOr("AETHI_INITIAL_RECIPIENT", config.admin);
        config.initialSupply = vm.envOr("AETHI_INITIAL_SUPPLY", DEFAULT_INITIAL_SUPPLY);
        config.supplyCap = vm.envOr("AETHI_SUPPLY_CAP", DEFAULT_SUPPLY_CAP);
        config.rewardsDuration = vm.envOr("AETHI_REWARDS_DURATION", DEFAULT_REWARDS_DURATION);
        config.unstakeCooldown = vm.envOr("AETHI_UNSTAKE_COOLDOWN", DEFAULT_UNSTAKE_COOLDOWN);
        config.minStakeToPlay = vm.envOr("AETHI_MIN_STAKE_TO_PLAY", DEFAULT_MIN_STAKE_TO_PLAY);
        config.entryFee = vm.envOr("AETHI_ENTRY_FEE", DEFAULT_ENTRY_FEE);
        config.stakeBoostCapBps = vm.envOr("AETHI_STAKE_BOOST_CAP_BPS", DEFAULT_STAKE_BOOST_CAP_BPS);
        config.maxSeasonRound = vm.envOr("AETHI_MAX_SEASON_ROUND", DEFAULT_MAX_SEASON_ROUND);
        config.actionTimeout = vm.envOr("AETHI_ACTION_TIMEOUT", DEFAULT_ACTION_TIMEOUT);
        config.claimPeriod = vm.envOr("AETHI_CLAIM_PERIOD", DEFAULT_CLAIM_PERIOD);
    }
}
