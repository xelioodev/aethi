// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {AethiGameTypes} from "./AethiGameTypes.sol";
import {IAethiItems} from "../interfaces/IAethiItems.sol";
import {IAethiStaking} from "../interfaces/IAethiStaking.sol";

/// @title AethiGameState
/// @notice Shared storage, events, and errors for the Aethi game coordinator.
abstract contract AethiGameState is AccessControl, EIP712, Pausable, ReentrancyGuard {
    bytes32 public constant SEASON_MANAGER_ROLE = keccak256("SEASON_MANAGER_ROLE");
    bytes32 public constant GAME_OPERATOR_ROLE = keccak256("GAME_OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    bytes32 public constant BATTLE_RESULT_TYPEHASH = keccak256(
        "BattleResult(uint256 seasonId,address player,uint256 round,uint256 baseScore,bool wonBattle,uint256 deadline)"
    );

    uint256 public constant MAX_ACTION_ROUND = type(uint64).max;
    uint256 public constant MAX_BATCH_RESOLVE = 50;

    IERC20 public immutable token;
    IAethiStaking public immutable staking;
    IAethiItems public itemCollection;

    address public treasury;
    uint256 public minStakeToPlay;
    uint256 public entryFee;
    uint256 public stakeBoostCapBps;
    uint256 public maxSeasonRound;
    uint256 public actionTimeout;
    uint256 public claimPeriod;
    uint256 public nextSeasonId = 1;

    mapping(uint256 seasonId => AethiGameTypes.Season season) public seasons;
    mapping(uint256 seasonId => mapping(address player => bool joined)) public hasJoined;
    mapping(uint256 seasonId => mapping(address player => uint256 stakeSnapshot)) public stakeSnapshots;
    mapping(uint256 seasonId => mapping(address player => uint256 score)) public scores;
    mapping(uint256 seasonId => mapping(address player => uint256 winStreak)) public winStreaks;
    mapping(uint256 seasonId => mapping(address player => bool claimed)) public hasClaimed;
    mapping(uint256 seasonId => mapping(address player => uint256 tokenId)) public equippedItems;
    mapping(uint256 seasonId => mapping(address player => AethiGameTypes.BattleAction action)) public pendingActions;
    mapping(uint256 seasonId => mapping(address player => uint256 round)) public pendingActionRounds;
    mapping(uint256 seasonId => mapping(address player => uint256 deadline)) public pendingActionDeadlines;
    mapping(uint256 seasonId => mapping(address player => mapping(uint256 round => bool resolved))) public
        resolvedBattles;

    event SeasonCreated(
        uint256 indexed seasonId, uint64 startTime, uint64 endTime, uint256 rewardPool, uint256 claimDeadline
    );
    event SeasonCancelled(uint256 indexed seasonId, address indexed recipient, uint256 refundedAmount);
    event SeasonDustSwept(uint256 indexed seasonId, address indexed recipient, uint256 amount);
    event SeasonJoined(uint256 indexed seasonId, address indexed player, uint256 stakeSnapshot);
    event ItemCollectionUpdated(address indexed itemCollection);
    event ItemEquipped(uint256 indexed seasonId, address indexed player, uint256 indexed tokenId, uint256 powerBps);
    event BattleActionCommitted(
        uint256 indexed seasonId,
        address indexed player,
        uint256 indexed round,
        AethiGameTypes.BattleAction action,
        uint256 actionDeadline
    );
    event BattleActionExpired(uint256 indexed seasonId, address indexed player, uint256 indexed round);
    event BattleResolved(
        uint256 indexed seasonId,
        address indexed player,
        uint256 indexed round,
        AethiGameTypes.BattleAction action,
        uint256 baseScore,
        uint256 boostedScore,
        uint256 streak
    );
    event ScoreRecorded(uint256 indexed seasonId, address indexed player, uint256 scoreDelta, uint256 totalPlayerScore);
    event SeasonFinalized(uint256 indexed seasonId, uint256 totalScore, uint256 claimDeadline);
    event SeasonRewardClaimed(uint256 indexed seasonId, address indexed player, uint256 amount);
    event GameConfigUpdated(address treasury, uint256 minStakeToPlay, uint256 entryFee, uint256 stakeBoostCapBps);

    error AlreadyClaimed();
    error AlreadyJoined();
    error ActionExpired();
    error ClaimWindowActive();
    error DustAlreadySwept();
    error InvalidAmount();
    error InvalidAction();
    error InvalidAttestation();
    error InvalidBatch();
    error InvalidBoost();
    error InvalidItemOwner();
    error InvalidRound();
    error InvalidSeason();
    error NoPendingAction();
    error NoItemCharges();
    error PendingAction();
    error ResultAlreadyResolved();
    error SeasonActive();
    error SeasonCancelledError();
    error SeasonClosed();
    error SeasonNotFinalized();
    error TooLittleStake();
    error ZeroAddress();

    constructor(
        IERC20 token_,
        IAethiStaking staking_,
        address treasury_,
        address admin,
        uint256 minStakeToPlay_,
        uint256 entryFee_,
        uint256 stakeBoostCapBps_,
        uint256 maxSeasonRound_,
        uint256 actionTimeout_,
        uint256 claimPeriod_
    ) EIP712("AethiGame", "1") {
        if (
            address(token_) == address(0) || address(staking_) == address(0) || treasury_ == address(0)
                || admin == address(0)
        ) {
            revert ZeroAddress();
        }
        _validateGameConfig(stakeBoostCapBps_, maxSeasonRound_, actionTimeout_, claimPeriod_);

        token = token_;
        staking = staking_;
        treasury = treasury_;
        minStakeToPlay = minStakeToPlay_;
        entryFee = entryFee_;
        stakeBoostCapBps = stakeBoostCapBps_;
        maxSeasonRound = maxSeasonRound_;
        actionTimeout = actionTimeout_;
        claimPeriod = claimPeriod_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SEASON_MANAGER_ROLE, admin);
        _grantRole(GAME_OPERATOR_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    function _validateGameConfig(
        uint256 stakeBoostCapBps_,
        uint256 maxSeasonRound_,
        uint256 actionTimeout_,
        uint256 claimPeriod_
    ) internal pure {
        if (stakeBoostCapBps_ > 10_000) {
            revert InvalidBoost();
        }
        if (maxSeasonRound_ == 0 || maxSeasonRound_ > MAX_ACTION_ROUND || actionTimeout_ == 0 || claimPeriod_ == 0) {
            revert InvalidSeason();
        }
    }
}
