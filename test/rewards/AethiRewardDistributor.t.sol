// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {AethiRewardDistributor} from "../../src/rewards/AethiRewardDistributor.sol";
import {AethiToken} from "../../src/token/AethiToken.sol";

contract AethiRewardDistributorTest is Test {
    AethiToken internal token;
    AethiRewardDistributor internal distributor;

    address internal admin = address(0xA11CE);
    address internal alice = address(0xA1);

    function setUp() public {
        token = new AethiToken(admin, admin, 1_000 ether, 10_000 ether);
        distributor = new AethiRewardDistributor(token, admin);

        vm.startPrank(admin);
        token.approve(address(distributor), 100 ether);
        distributor.fund(100 ether);
        vm.stopPrank();
    }

    function testDistributorCanSendFundedRewards() public {
        bytes32 reason = keccak256("SEASON_BONUS");

        vm.prank(admin);
        distributor.distribute(alice, 25 ether, reason);

        assertEq(token.balanceOf(alice), 25 ether);
        assertEq(token.balanceOf(address(distributor)), 75 ether);
    }

    function testPauseBlocksDistribution() public {
        vm.prank(admin);
        distributor.pause();

        vm.prank(admin);
        vm.expectRevert();
        distributor.distribute(alice, 1 ether, keccak256("PAUSED"));
    }
}
