// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {AethiGame} from "../../src/game/AethiGame.sol";
import {AethiGameTypes} from "../../src/game/AethiGameTypes.sol";
import {AethiItems} from "../../src/items/AethiItems.sol";
import {AethiStaking} from "../../src/staking/AethiStaking.sol";
import {AethiToken} from "../../src/token/AethiToken.sol";

contract AethiGameInvariantTest is Test {
    uint256 internal adminKey = 0xA11CE;
    address internal admin = vm.addr(adminKey);
    address internal treasury = address(0xBEEF);
    address internal alice = address(0xA1);
    address internal bob = address(0xB0B);

    AethiToken internal token;
    AethiStaking internal staking;
    AethiGame internal game;

    function setUp() public {
        token = new AethiToken(admin, admin, 20_000 ether, 100_000 ether);
        AethiItems items = new AethiItems(admin);
        staking = new AethiStaking(token, token, admin, 30 days, 1 days);
        game = new AethiGame(token, staking, treasury, admin, 100 ether, 1 ether, 2_000, 100, 15 minutes, 7 days);

        vm.startPrank(admin);
        game.setItemCollection(items);
        items.grantRole(items.ITEM_CONSUMER_ROLE(), address(game));
        assertTrue(token.transfer(alice, 1_000 ether));
        assertTrue(token.transfer(bob, 1_000 ether));
        vm.stopPrank();

        _stake(alice, 200 ether);
        _stake(bob, 300 ether);
    }

    function testSeasonPayoutsNeverExceedRewardPool() public {
        uint256 rewardPool = 501 ether;
        uint256 seasonId = _createSeason(rewardPool);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        game.joinSeason(seasonId);
        vm.prank(bob);
        game.joinSeason(seasonId);

        _resolve(seasonId, alice, 1, 100, true);
        _resolve(seasonId, bob, 1, 300, true);

        vm.warp(block.timestamp + 101);
        vm.prank(admin);
        game.finalizeSeason(seasonId);

        vm.prank(alice);
        uint256 aliceReward = game.claimSeasonReward(seasonId);
        vm.prank(bob);
        uint256 bobReward = game.claimSeasonReward(seasonId);

        assertLe(aliceReward + bobReward, rewardPool);
    }

    function testStakingPrincipalMatchesUserBalances() public view {
        assertEq(staking.totalStaked(), 500 ether);
        assertEq(staking.stakedBalanceOf(alice) + staking.stakedBalanceOf(bob), staking.totalStaked());
    }

    function _stake(address player, uint256 amount) internal {
        vm.startPrank(player);
        token.approve(address(staking), amount);
        staking.stake(amount);
        token.approve(address(game), 10 ether);
        vm.stopPrank();
    }

    function _createSeason(uint256 rewardPool) internal returns (uint256 seasonId) {
        vm.startPrank(admin);
        token.approve(address(game), rewardPool);
        seasonId = game.createSeason(uint64(block.timestamp + 1), uint64(block.timestamp + 101), rewardPool);
        vm.stopPrank();
    }

    function _resolve(uint256 seasonId, address player, uint256 round, uint256 baseScore, bool wonBattle) internal {
        vm.prank(player);
        game.commitBattleAction(seasonId, round, AethiGameTypes.BattleAction.Strike);

        AethiGameTypes.BattleResult memory result = AethiGameTypes.BattleResult({
            seasonId: seasonId,
            player: player,
            round: round,
            baseScore: baseScore,
            wonBattle: wonBattle,
            deadline: block.timestamp + 1 hours
        });

        bytes32 digest = game.hashBattleResult(result);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminKey, digest);
        game.resolveBattle(result, abi.encodePacked(r, s, v));
    }
}
