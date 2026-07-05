// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title AethiItemTypes
/// @notice Shared item schema constants for Aethi equipment NFTs.
library AethiItemTypes {
    uint256 internal constant MAX_POWER_BPS = 5_000;
    uint256 internal constant MAX_CHARGES = 100;

    bytes32 internal constant MINT_AUTHORIZATION_TYPEHASH = keccak256(
        "MintAuthorization(address player,uint256 itemType,uint8 itemClass,uint8 actionAffinity,uint256 powerBps,uint256 charges,bytes32 uriHash,uint256 nonce,uint256 deadline)"
    );
}
