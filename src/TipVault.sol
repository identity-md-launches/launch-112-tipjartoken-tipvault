// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Adminless custody of TIPS principal and pro-rata distribution of voluntary ETH tips.
/// @dev Only the immutable, ordinary non-rebasing TipJarToken is supported. No owner or initialization step.
contract TipVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant REWARD_SCALE = 1e18;
    IERC20 public immutable token;
    uint256 public totalStaked;
    mapping(address account => uint256 amount) public stakedOf;

    uint256 public rewardPerShare;
    uint256 public queuedTips;
    mapping(address account => uint256 index) private _paidIndex;
    mapping(address account => uint256 amount) private _accrued;
    // Fractions of one wei, in units of 1 / REWARD_SCALE, remain with their original beneficiary.
    mapping(address account => uint256 fraction) private _remainder;

    error InvalidToken();
    error ZeroAmount();
    error InsufficientStake();
    error NoRewards();
    error ETHTransferFailed();

    event Staked(address indexed account, uint256 amount);
    event Unstaked(address indexed account, uint256 amount);
    /// @param distributed Includes queued zero-stake tips; zero when there are no stakers.
    event Tipped(address indexed sender, uint256 amount, uint256 distributed);
    event Claimed(address indexed account, uint256 amount);

    /// @param token_ The launch token, resolved from the manifest's $token address reference.
    constructor(address token_) {
        if (token_ == address(0) || token_.code.length == 0) revert InvalidToken();
        token = IERC20(token_);
    }

    /// @notice Stake an approved amount of TIPS. Existing rewards are settled before changing stake.
    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _checkpoint(msg.sender);
        stakedOf[msg.sender] += amount;
        totalStaked += amount;
        emit Staked(msg.sender, amount);
        token.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Withdraw principal while retaining all previously accrued ETH and fractional rewards.
    function unstake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (amount > stakedOf[msg.sender]) revert InsufficientStake();
        _checkpoint(msg.sender);
        stakedOf[msg.sender] -= amount;
        totalStaked -= amount;
        emit Unstaked(msg.sender, amount);
        token.safeTransfer(msg.sender, amount);
    }

    /// @notice Distribute ETH among current stakes, or queue it if there are none.
    function tip() external payable nonReentrant {
        _tip();
    }

    receive() external payable nonReentrant {
        _tip();
    }

    /// @notice Pay the caller's whole-wei rewards. A rejected payment reverts all accounting changes.
    function claim() external nonReentrant returns (uint256 amount) {
        _checkpoint(msg.sender);
        amount = _accrued[msg.sender];
        if (amount == 0) revert NoRewards();
        _accrued[msg.sender] = 0;
        emit Claimed(msg.sender, amount);
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) revert ETHTransferFailed();
    }

    /// @notice Currently withdrawable whole wei; queued zero-stake tips are not yet allocated.
    function claimable(address account) external view returns (uint256) {
        (uint256 earned,) = _pending(account);
        return _accrued[account] + earned;
    }

    function _tip() private {
        if (msg.value == 0) revert ZeroAmount();
        uint256 distributed = 0;
        if (totalStaked == 0) {
            queuedTips += msg.value;
        } else {
            // Only a positive tip with active stake triggers distribution of the queue.
            distributed = msg.value + queuedTips;
            queuedTips = 0;
            rewardPerShare += Math.mulDiv(distributed, REWARD_SCALE, totalStaked);
        }
        emit Tipped(msg.sender, msg.value, distributed);
    }

    function _checkpoint(address account) private {
        (uint256 earned, uint256 remainder) = _pending(account);
        _accrued[account] += earned;
        _remainder[account] = remainder;
        _paidIndex[account] = rewardPerShare;
    }

    function _pending(address account) private view returns (uint256 earned, uint256 remainder) {
        uint256 delta = rewardPerShare - _paidIndex[account];
        uint256 stakeAmount = stakedOf[account];
        earned = Math.mulDiv(stakeAmount, delta, REWARD_SCALE);
        uint256 fractions = mulmod(stakeAmount, delta, REWARD_SCALE) + _remainder[account];
        earned += fractions / REWARD_SCALE;
        remainder = fractions % REWARD_SCALE;
    }
}
