// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {AethiStaking} from "../../src/staking/AethiStaking.sol";
import {AethiToken} from "../../src/token/AethiToken.sol";

contract AethiStakingTest is Test {
    AethiToken internal token;
    AethiStaking internal staking;

    address internal admin = address(0xA11CE);
    address internal alice = address(0xA1);
    uint256 internal constant UNSTAKE_COOLDOWN = 1 days;

    function setUp() public {
        token = new AethiToken(admin, admin, 10_000 ether, 100_000 ether);
        staking = new AethiStaking(token, token, admin, 100 seconds, UNSTAKE_COOLDOWN);

        vm.startPrank(admin);
        assertTrue(token.transfer(alice, 1_000 ether));
        token.approve(address(staking), 1_000 ether);
        staking.fundRewards(100 ether);
        vm.stopPrank();
    }

    function testStakeAccruesAndClaimsRewards() public {
        vm.startPrank(alice);
        token.approve(address(staking), 100 ether);
        staking.stake(100 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 50 seconds);
        assertApproxEqAbs(staking.pendingRewards(alice), 50 ether, 1 wei);

        vm.prank(alice);
        uint256 claimed = staking.claim();

        assertApproxEqAbs(claimed, 50 ether, 1 wei);
        assertApproxEqAbs(token.balanceOf(alice), 950 ether, 1 wei);
    }

    function testUnstakeReturnsPrincipal() public {
        vm.startPrank(alice);
        token.approve(address(staking), 100 ether);
        staking.stake(100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(AethiStaking.PositionLocked.selector, block.timestamp + UNSTAKE_COOLDOWN)
        );
        staking.unstake(40 ether);
        vm.warp(block.timestamp + UNSTAKE_COOLDOWN);
        staking.unstake(40 ether);
        vm.stopPrank();

        assertEq(staking.stakedBalanceOf(alice), 60 ether);
        assertEq(token.balanceOf(alice), 940 ether);
    }

    function testTopUpRefreshesCooldown() public {
        vm.startPrank(alice);
        token.approve(address(staking), 150 ether);
        staking.stake(100 ether);
        vm.warp(block.timestamp + 12 hours);
        staking.stake(50 ether);

        uint256 availableAt = block.timestamp + UNSTAKE_COOLDOWN;
        assertEq(staking.unstakeAvailableAt(alice), availableAt);
        vm.expectRevert(abi.encodeWithSelector(AethiStaking.PositionLocked.selector, availableAt));
        staking.unstake(1 ether);
        vm.stopPrank();
    }
}
