// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title AethiToken
/// @notice ERC20 token for the Aethi game economy.
/// @dev The token uses role-based minting and an immutable cap to avoid unbounded emissions.
contract AethiToken is ERC20, ERC20Pausable, ERC20Permit, AccessControl {
    /// @notice Role allowed to mint new AETHI up to the immutable cap.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Role allowed to pause and unpause token transfers.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Maximum token supply that can ever exist.
    uint256 public immutable cap;

    /// @notice Reverts when a mint would exceed the immutable supply cap.
    error CapExceeded(uint256 cap, uint256 requestedSupply);

    /// @notice Reverts when an address parameter is the zero address.
    error ZeroAddress();

    /// @param admin Account receiving the default admin, minter, and pauser roles.
    /// @param initialRecipient Account receiving the initial token supply.
    /// @param initialSupply Amount minted during deployment.
    /// @param supplyCap Maximum token supply.
    constructor(address admin, address initialRecipient, uint256 initialSupply, uint256 supplyCap)
        ERC20("Aethi", "AETHI")
        ERC20Permit("Aethi")
    {
        if (admin == address(0) || initialRecipient == address(0)) {
            revert ZeroAddress();
        }
        if (initialSupply > supplyCap) {
            revert CapExceeded(supplyCap, initialSupply);
        }

        cap = supplyCap;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        _mint(initialRecipient, initialSupply);
    }

    /// @notice Mints AETHI to an account.
    /// @param to Account receiving minted tokens.
    /// @param amount Amount of tokens to mint.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        uint256 requestedSupply = totalSupply() + amount;
        if (requestedSupply > cap) {
            revert CapExceeded(cap, requestedSupply);
        }
        _mint(to, amount);
    }

    /// @notice Pauses token transfers, minting, and burning.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resumes token transfers, minting, and burning.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @dev Required override for ERC20Pausable in OpenZeppelin Contracts v5.
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }

    /// @dev Required override because both AccessControl and ERC20Permit inherit ERC165-capable bases.
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
