// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {AethiGame} from "../../src/game/AethiGame.sol";
import {AethiGameState} from "../../src/game/AethiGameState.sol";
import {AethiGameTypes} from "../../src/game/AethiGameTypes.sol";
import {AethiItems} from "../../src/items/AethiItems.sol";
import {AethiStaking} from "../../src/staking/AethiStaking.sol";
import {AethiToken} from "../../src/token/AethiToken.sol";

contract AethiGameTest is Test {
    uint256 internal adminKey = 0xA11CE;
    address internal admin = vm.addr(adminKey);

    AethiToken internal token;
    AethiItems internal items;
    AethiStaking internal staking;
    AethiGame internal game;

    address internal treasury = address(0xBEEF);
    address internal alice = address(0xA1);
    address internal bob = address(0xB0B);

    function setUp() public {
        token = new AethiToken(admin, admin, 20_000 ether, 100_000 ether);
        items = new AethiItems(admin);
        staking = new AethiStaking(token, token, admin, 30 days, 1 days);
        game = new AethiGame(token, staking, treasury, admin, 100 ether, 1 ether, 2_000, 100, 15 minutes, 7 days);

        vm.startPrank(admin);
        game.setItemCollection(items);
        items.grantRole(items.ITEM_CONSUMER_ROLE(), address(game));
        assertTrue(token.transfer(alice, 1_000 ether));
        assertTrue(token.transfer(bob, 1_000 ether));
        vm.stopPrank();

        _stakeAndApprove(alice, 200 ether);
        _stakeAndApprove(bob, 200 ether);
    }

    function testSeasonFlowPaysProRataReward() public {
        uint256 seasonId = _createSeason(500 ether);

        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        game.joinSeason(seasonId);

        vm.prank(admin);
        game.recordScore(seasonId, alice, 25);

        assertEq(game.stakeSnapshots(seasonId, alice), 200 ether);
        assertEq(game.scores(seasonId, alice), 30);

        vm.warp(block.timestamp + 101);

        vm.prank(admin);
        game.finalizeSeason(seasonId);

        vm.prank(alice);
        uint256 reward = game.claimSeasonReward(seasonId);

        assertEq(reward, 500 ether);
        assertEq(token.balanceOf(treasury), 1 ether);
    }

    function testBattleActionResolvesWithSignedResultAndConsumesItemCharge() public {
        uint256 itemId =
            _mintItem(alice, 7, 2, uint8(AethiGameTypes.BattleAction.Strike), 2_000, 2, "ipfs://blade.json", 0);
        uint256 seasonId = _createSeason(500 ether);

        vm.warp(block.timestamp + 1);

        vm.startPrank(alice);
        game.joinSeason(seasonId);
        game.equipItem(seasonId, itemId);
        game.commitBattleAction(seasonId, 1, AethiGameTypes.BattleAction.Strike);
        vm.stopPrank();

        AethiGameTypes.BattleResult memory result =
            _battleResult(seasonId, alice, 1, 100, true, block.timestamp + 1 hours);
        game.resolveBattle(result, _signBattle(result));

        assertEq(game.winStreaks(seasonId, alice), 1);
        assertEq(uint256(game.pendingActions(seasonId, alice)), uint256(AethiGameTypes.BattleAction.None));
        assertEq(items.itemCharges(itemId), 1);
        assertEq(game.scores(seasonId, alice), 170);
    }

    function testBatchResolveBattles() public {
        uint256 seasonId = _createSeason(500 ether);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        game.joinSeason(seasonId);
        vm.prank(bob);
        game.joinSeason(seasonId);

        vm.prank(alice);
        game.commitBattleAction(seasonId, 1, AethiGameTypes.BattleAction.Guard);
        vm.prank(bob);
        game.commitBattleAction(seasonId, 1, AethiGameTypes.BattleAction.Focus);

        AethiGameTypes.BattleResult[] memory results = new AethiGameTypes.BattleResult[](2);
        bytes[] memory signatures = new bytes[](2);
        results[0] = _battleResult(seasonId, alice, 1, 100, true, block.timestamp + 1 hours);
        results[1] = _battleResult(seasonId, bob, 1, 100, false, block.timestamp + 1 hours);
        signatures[0] = _signBattle(results[0]);
        signatures[1] = _signBattle(results[1]);

        game.resolveBattles(results, signatures);

        assertEq(game.scores(seasonId, alice), 134);
        assertEq(game.scores(seasonId, bob), 120);
    }

    function testActionExpiresAndCanBeCleared() public {
        uint256 seasonId = _createSeason(500 ether);
        vm.warp(block.timestamp + 1);

        vm.startPrank(alice);
        game.joinSeason(seasonId);
        game.commitBattleAction(seasonId, 1, AethiGameTypes.BattleAction.Strike);
        vm.stopPrank();

        vm.warp(block.timestamp + 16 minutes);
        game.clearExpiredAction(seasonId, alice);

        assertEq(uint256(game.pendingActions(seasonId, alice)), uint256(AethiGameTypes.BattleAction.None));
    }

    function testResolvedBattleCannotBeReplayed() public {
        uint256 seasonId = _createSeason(500 ether);
        vm.warp(block.timestamp + 1);

        vm.startPrank(alice);
        game.joinSeason(seasonId);
        game.commitBattleAction(seasonId, 1, AethiGameTypes.BattleAction.Strike);
        vm.stopPrank();

        AethiGameTypes.BattleResult memory result =
            _battleResult(seasonId, alice, 1, 100, true, block.timestamp + 1 hours);
        bytes memory signature = _signBattle(result);

        game.resolveBattle(result, signature);

        vm.prank(alice);
        vm.expectRevert(AethiGameState.InvalidRound.selector);
        game.commitBattleAction(seasonId, 1, AethiGameTypes.BattleAction.Strike);

        vm.expectRevert(AethiGameState.ResultAlreadyResolved.selector);
        game.resolveBattle(result, signature);
    }

    function testCannotEquipItemWithoutCharges() public {
        uint256 itemId =
            _mintItem(alice, 7, 2, uint8(AethiGameTypes.BattleAction.Strike), 2_000, 0, "ipfs://empty.json", 0);
        uint256 seasonId = _createSeason(500 ether);
        vm.warp(block.timestamp + 1);

        vm.startPrank(alice);
        game.joinSeason(seasonId);
        vm.expectRevert(AethiGameState.NoItemCharges.selector);
        game.equipItem(seasonId, itemId);
        vm.stopPrank();
    }

    function testCannotResolveBattleWithoutCommittedAction() public {
        uint256 seasonId = _createSeason(500 ether);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        game.joinSeason(seasonId);

        AethiGameTypes.BattleResult memory result =
            _battleResult(seasonId, alice, 1, 100, true, block.timestamp + 1 hours);
        bytes memory signature = _signBattle(result);
        vm.expectRevert(AethiGameState.InvalidRound.selector);
        game.resolveBattle(result, signature);
    }

    function testCancelSeasonRefundsRewardPoolBeforeStart() public {
        uint256 seasonId = _createSeason(500 ether);
        uint256 beforeBalance = token.balanceOf(treasury);

        vm.prank(admin);
        game.cancelSeason(seasonId, treasury);

        assertEq(token.balanceOf(treasury), beforeBalance + 500 ether);
    }

    function testCannotCancelAfterSeasonStarts() public {
        uint256 seasonId = _createSeason(500 ether);
        vm.warp(block.timestamp + 1);

        vm.prank(admin);
        vm.expectRevert(AethiGameState.SeasonActive.selector);
        game.cancelSeason(seasonId, treasury);
    }

    function testSweepSeasonDustAfterClaimWindow() public {
        uint256 seasonId = _createSeason(501 ether);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        game.joinSeason(seasonId);
        vm.prank(bob);
        game.joinSeason(seasonId);

        vm.prank(admin);
        game.recordScore(seasonId, alice, 1);
        vm.prank(admin);
        game.recordScore(seasonId, bob, 2);

        vm.warp(block.timestamp + 101);
        vm.prank(admin);
        game.finalizeSeason(seasonId);

        vm.prank(alice);
        game.claimSeasonReward(seasonId);

        vm.warp(block.timestamp + 7 days + 1);
        uint256 beforeBalance = token.balanceOf(treasury);
        vm.prank(admin);
        game.sweepSeasonDust(seasonId, treasury);

        assertGt(token.balanceOf(treasury), beforeBalance);
    }

    function testTransferredEquippedItemCannotBoostScore() public {
        uint256 itemId =
            _mintItem(alice, 7, 2, uint8(AethiGameTypes.BattleAction.Strike), 2_000, 2, "ipfs://blade.json", 0);
        uint256 seasonId = _createSeason(500 ether);

        vm.warp(block.timestamp + 1);

        vm.startPrank(alice);
        game.joinSeason(seasonId);
        game.equipItem(seasonId, itemId);
        items.transferFrom(alice, bob, itemId);
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(AethiGameState.InvalidItemOwner.selector);
        game.recordScore(seasonId, alice, 100);
    }

    function testCannotJoinWithoutMinimumStake() public {
        address charlie = address(0xCAFE);
        vm.prank(admin);
        assertTrue(token.transfer(charlie, 10 ether));

        uint256 seasonId = _createSeason(100 ether);
        vm.warp(block.timestamp + 1);

        vm.startPrank(charlie);
        token.approve(address(game), 1 ether);
        vm.expectRevert(AethiGameState.TooLittleStake.selector);
        game.joinSeason(seasonId);
        vm.stopPrank();
    }

    function _createSeason(uint256 rewardPool) internal returns (uint256 seasonId) {
        uint64 startTime = uint64(block.timestamp + 1);
        uint64 endTime = uint64(block.timestamp + 101);

        vm.startPrank(admin);
        token.approve(address(game), rewardPool);
        seasonId = game.createSeason(startTime, endTime, rewardPool);
        vm.stopPrank();
    }

    function _stakeAndApprove(address player, uint256 amount) internal {
        vm.startPrank(player);
        token.approve(address(staking), amount);
        staking.stake(amount);
        token.approve(address(game), 10 ether);
        vm.stopPrank();
    }

    function _mintItem(
        address player,
        uint256 itemType,
        uint8 itemClass,
        uint8 actionAffinity,
        uint256 powerBps,
        uint256 charges,
        string memory tokenUri,
        uint256 nonce
    ) internal returns (uint256) {
        uint256 deadline = block.timestamp + 1 days;
        bytes memory signature =
            _signMint(player, itemType, itemClass, actionAffinity, powerBps, charges, tokenUri, nonce, deadline);
        return items.mintWithSignature(
            player, itemType, itemClass, actionAffinity, powerBps, charges, tokenUri, nonce, deadline, signature
        );
    }

    function _battleResult(
        uint256 seasonId,
        address player,
        uint256 round,
        uint256 baseScore,
        bool wonBattle,
        uint256 deadline
    ) internal pure returns (AethiGameTypes.BattleResult memory) {
        return AethiGameTypes.BattleResult({
            seasonId: seasonId,
            player: player,
            round: round,
            baseScore: baseScore,
            wonBattle: wonBattle,
            deadline: deadline
        });
    }

    function _signBattle(AethiGameTypes.BattleResult memory result) internal view returns (bytes memory) {
        bytes32 digest = game.hashBattleResult(result);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signMint(
        address player,
        uint256 itemType,
        uint8 itemClass,
        uint8 actionAffinity,
        uint256 powerBps,
        uint256 charges,
        string memory tokenUri,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 digest = items.hashMintAuthorization(
            player, itemType, itemClass, actionAffinity, powerBps, charges, tokenUri, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
