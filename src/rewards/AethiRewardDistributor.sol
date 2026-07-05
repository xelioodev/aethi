// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title AethiRewardDistributor
/// @notice Custodial reward vault for controlled AETHI distributions.
contract AethiRewardDistributor is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Role allowed to distribute funded rewards.
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    /// @notice Role allowed to pause and unpause distributions.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Token distributed by this vault.
    IERC20 public immutable rewardToken;

    event Funded(address indexed funder, uint256 amount);
    event Distributed(address indexed operator, address indexed recipient, uint256 amount, bytes32 indexed reason);
    event Recovered(address indexed token, address indexed recipient, uint256 amount);

    error InvalidAmount();
    error ZeroAddress();

    /// @param rewardToken_ Token held and distributed by the vault.
    /// @param admin Account receiving admin, distributor, and pauser roles.
    constructor(IERC20 rewardToken_, address admin) {
        if (address(rewardToken_) == address(0) || admin == address(0)) {
            revert ZeroAddress();
        }

        rewardToken = rewardToken_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DISTRIBUTOR_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    /// @notice Funds the vault with reward tokens.
    /// @param amount Amount transferred from the caller.
    function fund(uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert InvalidAmount();
        }

        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Funded(msg.sender, amount);
    }

    /// @notice Distributes rewards to a recipient.
    /// @param recipient Account receiving rewards.
    /// @param amount Amount of reward tokens to transfer.
    /// @param reason Off-chain correlation identifier for the reward reason.
    function distribute(address recipient, uint256 amount, bytes32 reason)
        external
        nonReentrant
        whenNotPaused
        onlyRole(DISTRIBUTOR_ROLE)
    {
        if (recipient == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }

        rewardToken.safeTransfer(recipient, amount);
        emit Distributed(msg.sender, recipient, amount, reason);
    }

    /// @notice Recovers tokens accidentally sent to this contract.
    /// @param token Token to recover.
    /// @param recipient Account receiving recovered tokens.
    /// @param amount Amount to recover.
    function recoverToken(IERC20 token, address recipient, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(token) == address(0) || recipient == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }

        token.safeTransfer(recipient, amount);
        emit Recovered(address(token), recipient, amount);
    }

    /// @notice Pauses reward distribution.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resumes reward distribution.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
