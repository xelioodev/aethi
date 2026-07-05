// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {AethiItems} from "../../src/items/AethiItems.sol";

contract AethiItemsTest is Test {
    uint256 internal signerKey = 0xA11CE;
    address internal admin = vm.addr(signerKey);
    address internal alice = address(0xA1);

    AethiItems internal items;

    function setUp() public {
        items = new AethiItems(admin);
    }

    function testMintWithSignatureMintsItemAndConsumesNonce() public {
        bytes memory signature = _signMint(alice, 1, 2, 1, 1_500, 3, "ipfs://sword.json", 0, block.timestamp + 1 days);

        uint256 tokenId = items.mintWithSignature(
            alice, 1, 2, 1, 1_500, 3, "ipfs://sword.json", 0, block.timestamp + 1 days, signature
        );

        assertEq(tokenId, 1);
        assertEq(items.ownerOf(tokenId), alice);
        assertEq(items.itemClass(tokenId), 2);
        assertEq(items.actionAffinity(tokenId), 1);
        assertEq(items.itemPower(tokenId), 1_500);
        assertEq(items.itemCharges(tokenId), 3);
        assertEq(items.tokenURI(tokenId), "ipfs://sword.json");
        assertEq(items.nonces(alice), 1);
    }

    function testConsumerCanSpendItemCharge() public {
        bytes memory signature = _signMint(alice, 1, 2, 1, 500, 1, "ipfs://shield.json", 0, block.timestamp + 1 days);
        uint256 tokenId = items.mintWithSignature(
            alice, 1, 2, 1, 500, 1, "ipfs://shield.json", 0, block.timestamp + 1 days, signature
        );

        vm.prank(admin);
        items.consumeItemCharge(tokenId);

        assertEq(items.itemCharges(tokenId), 0);

        vm.prank(admin);
        vm.expectRevert(AethiItems.NoCharges.selector);
        items.consumeItemCharge(tokenId);
    }

    function testRejectsReplay() public {
        bytes memory signature = _signMint(alice, 1, 1, 0, 500, 1, "ipfs://shield.json", 0, block.timestamp + 1 days);

        items.mintWithSignature(alice, 1, 1, 0, 500, 1, "ipfs://shield.json", 0, block.timestamp + 1 days, signature);

        vm.expectRevert();
        items.mintWithSignature(alice, 1, 1, 0, 500, 1, "ipfs://shield.json", 0, block.timestamp + 1 days, signature);
    }

    function testRejectsExpiredAuthorization() public {
        bytes memory signature = _signMint(alice, 1, 1, 0, 500, 1, "ipfs://expired.json", 0, block.timestamp);

        vm.warp(block.timestamp + 1);

        vm.expectRevert(AethiItems.AuthorizationExpired.selector);
        items.mintWithSignature(alice, 1, 1, 0, 500, 1, "ipfs://expired.json", 0, block.timestamp - 1, signature);
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
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
