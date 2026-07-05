// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {AethiToken} from "../../src/token/AethiToken.sol";

contract AethiTokenTest is Test {
    AethiToken internal token;

    address internal admin = address(0xA11CE);
    address internal treasury = address(0xB0B);
    address internal user = address(0xCAFE);

    function setUp() public {
        token = new AethiToken(admin, treasury, 1_000 ether, 10_000 ether);
    }

    function testConstructorMintsInitialSupplyAndSetsRoles() public view {
        assertEq(token.name(), "Aethi");
        assertEq(token.symbol(), "AETHI");
        assertEq(token.balanceOf(treasury), 1_000 ether);
        assertEq(token.cap(), 10_000 ether);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), admin));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), admin));
    }

    function testMintRespectsCap() public {
        vm.prank(admin);
        token.mint(user, 9_000 ether);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AethiToken.CapExceeded.selector, 10_000 ether, 10_001 ether));
        token.mint(user, 1 ether);
    }

    function testPauseBlocksTransfers() public {
        vm.prank(treasury);
        assertTrue(token.transfer(user, 10 ether));

        vm.prank(admin);
        token.pause();

        vm.prank(user);
        (bool success,) = address(token).call(abi.encodeCall(token.transfer, (treasury, 1 ether)));
        assertFalse(success);
    }
}
