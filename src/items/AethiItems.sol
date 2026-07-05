// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Pausable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

import {AethiItemTypes} from "./AethiItemTypes.sol";
import {IAethiItems} from "../interfaces/IAethiItems.sol";

/// @title AethiItems
/// @notice ERC721 equipment collection for the Aethi game.
/// @dev Item minting is authorized with EIP-712 signatures, per-account nonces, and deadlines.
contract AethiItems is IAethiItems, ERC721, ERC721Pausable, ERC721URIStorage, EIP712, Nonces, AccessControl {
    /// @notice Role allowed to sign item mint authorizations.
    bytes32 public constant ITEM_SIGNER_ROLE = keccak256("ITEM_SIGNER_ROLE");

    /// @notice Role allowed to pause and unpause item transfers and minting.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role allowed to update item metadata.
    bytes32 public constant METADATA_MANAGER_ROLE = keccak256("METADATA_MANAGER_ROLE");

    /// @notice Role allowed to consume item charges during gameplay.
    bytes32 public constant ITEM_CONSUMER_ROLE = keccak256("ITEM_CONSUMER_ROLE");

    /// @notice Maximum allowed item score boost in basis points.
    uint256 public constant MAX_POWER_BPS = AethiItemTypes.MAX_POWER_BPS;

    /// @notice Maximum charges assigned to a gameplay item.
    uint256 public constant MAX_CHARGES = AethiItemTypes.MAX_CHARGES;

    bytes32 public constant MINT_AUTHORIZATION_TYPEHASH = AethiItemTypes.MINT_AUTHORIZATION_TYPEHASH;

    uint256 private _nextTokenId = 1;
    mapping(uint256 tokenId => uint256 powerBps) private _itemPower;
    mapping(uint256 tokenId => uint8 classId) private _itemClass;
    mapping(uint256 tokenId => uint8 affinity) private _actionAffinity;
    mapping(uint256 tokenId => uint256 charges) private _itemCharges;
    mapping(uint256 tokenId => uint256 itemType) public itemTypes;

    event ItemMinted(
        address indexed player,
        uint256 indexed tokenId,
        uint256 indexed itemType,
        uint8 itemClass,
        uint8 actionAffinity,
        uint256 powerBps,
        uint256 charges,
        string tokenUri
    );
    event ItemURIUpdated(uint256 indexed tokenId, string tokenUri);
    event ItemChargeConsumed(uint256 indexed tokenId, uint256 remainingCharges);

    error AuthorizationExpired();
    error NoCharges();
    error InvalidPower();
    error InvalidSignature();
    error ZeroAddress();

    /// @param admin Account receiving admin, signer, pauser, and metadata manager roles.
    constructor(address admin) ERC721("Aethi Items", "AITEM") EIP712("AethiItems", "1") {
        if (admin == address(0)) {
            revert ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ITEM_SIGNER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(METADATA_MANAGER_ROLE, admin);
        _grantRole(ITEM_CONSUMER_ROLE, admin);
    }

    /// @notice Mints an item using an off-chain authorization signed by an item signer.
    /// @param player Account receiving the item.
    /// @param itemType Gameplay item category identifier.
    /// @param powerBps Score boost in basis points.
    /// @param tokenUri Metadata URI stored for the item.
    /// @param nonce Current player nonce included in the signed authorization.
    /// @param deadline Timestamp after which the authorization is invalid.
    /// @param signature EIP-712 signature from an account with `ITEM_SIGNER_ROLE`.
    /// @return tokenId Minted item identifier.
    function mintWithSignature(
        address player,
        uint256 itemType,
        uint8 itemClass_,
        uint8 actionAffinity_,
        uint256 powerBps,
        uint256 charges,
        string calldata tokenUri,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external whenNotPaused returns (uint256 tokenId) {
        if (player == address(0)) {
            revert ZeroAddress();
        }
        if (block.timestamp > deadline) {
            revert AuthorizationExpired();
        }
        if (powerBps > MAX_POWER_BPS) {
            revert InvalidPower();
        }
        if (charges > MAX_CHARGES) {
            revert InvalidPower();
        }

        bytes32 digest = hashMintAuthorization(
            player, itemType, itemClass_, actionAffinity_, powerBps, charges, tokenUri, nonce, deadline
        );
        address signer = ECDSA.recoverCalldata(digest, signature);
        if (!hasRole(ITEM_SIGNER_ROLE, signer)) {
            revert InvalidSignature();
        }

        _useCheckedNonce(player, nonce);

        tokenId = _nextTokenId++;
        itemTypes[tokenId] = itemType;
        _itemPower[tokenId] = powerBps;
        _itemClass[tokenId] = itemClass_;
        _actionAffinity[tokenId] = actionAffinity_;
        _itemCharges[tokenId] = charges;

        _safeMint(player, tokenId);
        _setTokenURI(tokenId, tokenUri);

        emit ItemMinted(player, tokenId, itemType, itemClass_, actionAffinity_, powerBps, charges, tokenUri);
    }

    /// @notice Updates the metadata URI for an item.
    /// @param tokenId Item token identifier.
    /// @param tokenUri New metadata URI.
    function setTokenURI(uint256 tokenId, string calldata tokenUri) external onlyRole(METADATA_MANAGER_ROLE) {
        _requireOwned(tokenId);
        _setTokenURI(tokenId, tokenUri);
        emit ItemURIUpdated(tokenId, tokenUri);
    }

    /// @notice Returns the EIP-712 digest for a mint authorization.
    function hashMintAuthorization(
        address player,
        uint256 itemType,
        uint8 itemClass_,
        uint8 actionAffinity_,
        uint256 powerBps,
        uint256 charges,
        string calldata tokenUri,
        uint256 nonce,
        uint256 deadline
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                MINT_AUTHORIZATION_TYPEHASH,
                player,
                itemType,
                itemClass_,
                actionAffinity_,
                powerBps,
                charges,
                keccak256(bytes(tokenUri)),
                nonce,
                deadline
            )
        );

        return _hashTypedDataV4(structHash);
    }

    /// @inheritdoc IAethiItems
    function itemPower(uint256 tokenId) external view returns (uint256) {
        _requireOwned(tokenId);
        return _itemPower[tokenId];
    }

    /// @inheritdoc IAethiItems
    function itemClass(uint256 tokenId) external view returns (uint8) {
        _requireOwned(tokenId);
        return _itemClass[tokenId];
    }

    /// @inheritdoc IAethiItems
    function actionAffinity(uint256 tokenId) external view returns (uint8) {
        _requireOwned(tokenId);
        return _actionAffinity[tokenId];
    }

    /// @inheritdoc IAethiItems
    function itemCharges(uint256 tokenId) external view returns (uint256) {
        _requireOwned(tokenId);
        return _itemCharges[tokenId];
    }

    /// @inheritdoc IAethiItems
    function consumeItemCharge(uint256 tokenId) external onlyRole(ITEM_CONSUMER_ROLE) {
        _requireOwned(tokenId);
        uint256 charges = _itemCharges[tokenId];
        if (charges == 0) {
            revert NoCharges();
        }

        unchecked {
            _itemCharges[tokenId] = charges - 1;
        }

        emit ItemChargeConsumed(tokenId, charges - 1);
    }

    /// @inheritdoc IAethiItems
    function ownerOf(uint256 tokenId) public view override(IAethiItems, IERC721, ERC721) returns (address) {
        return super.ownerOf(tokenId);
    }

    /// @notice Pauses item transfers and minting.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resumes item transfers and minting.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @dev Required override for ERC721Pausable.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Pausable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    /// @dev Required override for URI storage and access control.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @dev Required override for URI storage.
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }
}
