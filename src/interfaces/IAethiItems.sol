// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title IAethiItems
/// @notice Minimal item NFT interface consumed by the Aethi game layer.
interface IAethiItems {
    /// @notice Returns the owner of an item NFT.
    /// @param tokenId Item token identifier.
    /// @return The item owner.
    function ownerOf(uint256 tokenId) external view returns (address);

    /// @notice Returns the gameplay power value assigned to an item.
    /// @param tokenId Item token identifier.
    /// @return Power in basis points applied as a score boost.
    function itemPower(uint256 tokenId) external view returns (uint256);

    /// @notice Returns the gameplay class assigned to an item.
    function itemClass(uint256 tokenId) external view returns (uint8);

    /// @notice Returns the battle action affinity assigned to an item. Zero means any action.
    function actionAffinity(uint256 tokenId) external view returns (uint8);

    /// @notice Returns remaining battle charges for an item.
    function itemCharges(uint256 tokenId) external view returns (uint256);

    /// @notice Consumes one battle charge from an item.
    function consumeItemCharge(uint256 tokenId) external;
}
