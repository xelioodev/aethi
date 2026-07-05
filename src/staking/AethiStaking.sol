// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IAethiStaking} from "../interfaces/IAethiStaking.sol";

/// @title AethiStaking
/// @notice Single-token staking vault for AETHI rewards.
/// @dev Reward accounting uses accumulated rewards per share and never loops through stakers.
contract AethiStaking is IAethiStaking, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Role allowed to configure and fund reward emissions.
    bytes32 public constant REWARD_MANAGER_ROLE = keccak256("REWARD_MANAGER_ROLE");

    /// @notice Role allowed to pause and unpause staking operations.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 private constant ACC_REWARD_PRECISION = 1e24;

    /// @notice Token users stake.
    IERC20 public immutable stakingToken;

    /// @notice Token paid as staking rewards.
    IERC20 public immutable rewardToken;

    /// @notice Total amount currently staked.
    uint256 public totalStaked;

    /// @notice Reward emission rate per second.
    uint256 public rewardRate;

    /// @notice Timestamp when the current reward period ends.
    uint256 public periodFinish;

    /// @notice Duration used for newly funded reward periods.
    uint256 public rewardsDuration;

    /// @notice Delay after staking before the position can be withdrawn.
    uint256 public unstakeCooldown;

    /// @notice Last timestamp included in reward accounting.
    uint256 public lastRewardTime;

    /// @notice Accumulated reward per staked token.
    uint256 public accRewardPerShare;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 unpaidRewards;
    }

    mapping(address account => UserInfo info) private _users;
    mapping(address account => uint256 timestamp) public unstakeAvailableAt;

    /// @notice Emitted when a user stakes tokens.
    event Staked(address indexed user, uint256 amount);

    /// @notice Emitted when a user unstakes tokens.
    event Unstaked(address indexed user, uint256 amount);

    /// @notice Emitted when a user claims rewards.
    event RewardClaimed(address indexed user, uint256 amount);

    /// @notice Emitted when a new reward period is funded.
    event RewardFunded(address indexed funder, uint256 amount, uint256 duration);

    /// @notice Emitted when the reward duration changes.
    event RewardsDurationUpdated(uint256 duration);

    /// @notice Emitted when the unstake cooldown changes.
    event UnstakeCooldownUpdated(uint256 cooldown);

    error InvalidAmount();
    error PositionLocked(uint256 availableAt);
    error InvalidDuration();
    error RewardPeriodActive();
    error ZeroAddress();

    /// @param stakingToken_ Token accepted for staking.
    /// @param rewardToken_ Token paid as rewards.
    /// @param admin Account receiving admin, reward manager, and pauser roles.
    /// @param rewardsDuration_ Default reward period duration for funded rewards.
    /// @param unstakeCooldown_ Delay before newly staked tokens can be withdrawn.
    constructor(
        IERC20 stakingToken_,
        IERC20 rewardToken_,
        address admin,
        uint256 rewardsDuration_,
        uint256 unstakeCooldown_
    ) {
        if (address(stakingToken_) == address(0) || address(rewardToken_) == address(0) || admin == address(0)) {
            revert ZeroAddress();
        }
        if (rewardsDuration_ == 0) {
            revert InvalidDuration();
        }

        stakingToken = stakingToken_;
        rewardToken = rewardToken_;
        rewardsDuration = rewardsDuration_;
        unstakeCooldown = unstakeCooldown_;
        lastRewardTime = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REWARD_MANAGER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    /// @notice Stakes tokens and updates the caller's reward checkpoint.
    /// @param amount Amount of staking tokens to deposit.
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) {
            revert InvalidAmount();
        }

        _updatePool();
        UserInfo storage user = _users[msg.sender];
        _harvestToStorage(user);

        user.amount += amount;
        totalStaked += amount;
        user.rewardDebt = (user.amount * accRewardPerShare) / ACC_REWARD_PRECISION;
        unstakeAvailableAt[msg.sender] = block.timestamp + unstakeCooldown;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    /// @notice Unstakes tokens and updates the caller's reward checkpoint.
    /// @param amount Amount of staked tokens to withdraw.
    function unstake(uint256 amount) external nonReentrant {
        UserInfo storage user = _users[msg.sender];
        if (amount == 0 || amount > user.amount) {
            revert InvalidAmount();
        }
        if (block.timestamp < unstakeAvailableAt[msg.sender]) {
            revert PositionLocked(unstakeAvailableAt[msg.sender]);
        }

        _updatePool();
        _harvestToStorage(user);

        user.amount -= amount;
        totalStaked -= amount;
        user.rewardDebt = (user.amount * accRewardPerShare) / ACC_REWARD_PRECISION;

        stakingToken.safeTransfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    /// @notice Claims all pending staking rewards.
    /// @return reward Amount of rewards transferred to the caller.
    function claim() external nonReentrant returns (uint256 reward) {
        _updatePool();
        UserInfo storage user = _users[msg.sender];
        _harvestToStorage(user);

        reward = user.unpaidRewards;
        if (reward == 0) {
            return 0;
        }

        user.unpaidRewards = 0;
        user.rewardDebt = (user.amount * accRewardPerShare) / ACC_REWARD_PRECISION;
        rewardToken.safeTransfer(msg.sender, reward);

        emit RewardClaimed(msg.sender, reward);
    }

    /// @notice Withdraws staked tokens without claiming rewards.
    /// @dev This is intended as a safety exit during emergencies or integration failures.
    function emergencyWithdraw() external nonReentrant {
        _updatePool();

        UserInfo storage user = _users[msg.sender];
        uint256 amount = user.amount;
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (block.timestamp < unstakeAvailableAt[msg.sender]) {
            revert PositionLocked(unstakeAvailableAt[msg.sender]);
        }

        totalStaked -= amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.unpaidRewards = 0;

        stakingToken.safeTransfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    /// @notice Funds a new reward period.
    /// @param amount Amount of reward tokens transferred from the caller.
    function fundRewards(uint256 amount) external nonReentrant whenNotPaused onlyRole(REWARD_MANAGER_ROLE) {
        if (amount == 0) {
            revert InvalidAmount();
        }

        _updatePool();

        uint256 remainingReward;
        if (block.timestamp < periodFinish) {
            remainingReward = (periodFinish - block.timestamp) * rewardRate;
        }

        rewardToken.safeTransferFrom(msg.sender, address(this), amount);

        rewardRate = (amount + remainingReward) / rewardsDuration;
        if (rewardRate == 0) {
            revert InvalidAmount();
        }

        periodFinish = block.timestamp + rewardsDuration;
        lastRewardTime = block.timestamp;

        emit RewardFunded(msg.sender, amount, rewardsDuration);
    }

    /// @notice Updates the duration used for future reward periods.
    /// @param duration New reward duration in seconds.
    function setRewardsDuration(uint256 duration) external onlyRole(REWARD_MANAGER_ROLE) {
        if (duration == 0) {
            revert InvalidDuration();
        }
        if (block.timestamp < periodFinish) {
            revert RewardPeriodActive();
        }

        rewardsDuration = duration;
        emit RewardsDurationUpdated(duration);
    }

    /// @notice Updates the unstake cooldown applied to future and newly topped-up positions.
    /// @param cooldown New cooldown in seconds.
    function setUnstakeCooldown(uint256 cooldown) external onlyRole(REWARD_MANAGER_ROLE) {
        unstakeCooldown = cooldown;
        emit UnstakeCooldownUpdated(cooldown);
    }

    /// @notice Pauses new staking and reward funding.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resumes staking and reward funding.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @inheritdoc IAethiStaking
    function stakedBalanceOf(address account) external view returns (uint256) {
        return _users[account].amount;
    }

    /// @notice Returns pending rewards for an account.
    /// @param account Account to inspect.
    /// @return Pending reward amount.
    function pendingRewards(address account) public view returns (uint256) {
        UserInfo storage user = _users[account];
        uint256 updatedAccRewardPerShare = accRewardPerShare;

        uint256 applicableTime = _lastTimeRewardApplicable();
        if (applicableTime > lastRewardTime && totalStaked != 0) {
            uint256 reward = (applicableTime - lastRewardTime) * rewardRate;
            updatedAccRewardPerShare += (reward * ACC_REWARD_PRECISION) / totalStaked;
        }

        uint256 accumulated = (user.amount * updatedAccRewardPerShare) / ACC_REWARD_PRECISION;
        return user.unpaidRewards + accumulated - user.rewardDebt;
    }

    /// @notice Returns a user's staked amount, reward debt, and stored unpaid rewards.
    /// @param account Account to inspect.
    function userInfo(address account)
        external
        view
        returns (uint256 amount, uint256 rewardDebt, uint256 unpaidRewards)
    {
        UserInfo storage user = _users[account];
        return (user.amount, user.rewardDebt, user.unpaidRewards);
    }

    function _updatePool() internal {
        uint256 applicableTime = _lastTimeRewardApplicable();
        if (applicableTime <= lastRewardTime) {
            return;
        }

        if (totalStaked == 0) {
            lastRewardTime = applicableTime;
            return;
        }

        uint256 reward = (applicableTime - lastRewardTime) * rewardRate;
        accRewardPerShare += (reward * ACC_REWARD_PRECISION) / totalStaked;
        lastRewardTime = applicableTime;
    }

    function _harvestToStorage(UserInfo storage user) internal {
        uint256 accumulated = (user.amount * accRewardPerShare) / ACC_REWARD_PRECISION;
        if (accumulated > user.rewardDebt) {
            user.unpaidRewards += accumulated - user.rewardDebt;
        }
    }

    function _lastTimeRewardApplicable() internal view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }
}
