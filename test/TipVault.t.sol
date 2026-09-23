// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TipJarToken} from "../src/TipJarToken.sol";
import {TipVault} from "../src/TipVault.sol";

contract ClaimRecipient {
    TipVault public immutable vault;
    bool public rejectETH;
    bool public attack;
    bool public attackSucceeded;
    bytes public attackResult;
    uint256 public received;
    uint256 public claimableDuringCallback;
    bytes public callbackData;

    constructor(TipVault vault_) {
        vault = vault_;
        vault.token().approve(address(vault), type(uint256).max);
    }

    function deposit(uint256 amount) external {
        vault.stake(amount);
    }

    function configure(bool reject_, bool attack_, bytes calldata data) external {
        rejectETH = reject_;
        attack = attack_;
        callbackData = data;
    }

    function withdrawReward() external {
        vault.claim();
    }

    function withdrawStake(uint256 amount) external {
        vault.unstake(amount);
    }

    receive() external payable {
        require(!rejectETH, "recipient rejected ETH");
        received += msg.value;
        claimableDuringCallback = vault.claimable(address(this));
        if (attack) {
            (attackSucceeded, attackResult) = address(vault).call(callbackData);
        }
    }
}

contract TipVaultTest is Test {
    TipJarToken internal token;
    TipVault internal vault;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA401);

    event Staked(address indexed account, uint256 amount);
    event Unstaked(address indexed account, uint256 amount);
    event Tipped(address indexed sender, uint256 amount, uint256 distributed);
    event Claimed(address indexed account, uint256 amount);

    function setUp() public virtual {
        token = new TipJarToken();
        vault = new TipVault(address(token));
        _fund(ALICE);
        _fund(BOB);
        _fund(CAROL);
        vm.deal(address(this), 1_000_000 ether);
    }

    function _fund(address account) internal {
        token.transfer(account, 1_000_000 ether);
        vm.prank(account);
        token.approve(address(vault), type(uint256).max);
    }

    function _stake(address account, uint256 amount) internal {
        vm.prank(account);
        vault.stake(amount);
    }

    function _unstake(address account, uint256 amount) internal {
        vm.prank(account);
        vault.unstake(amount);
    }

    function _claim(address account) internal returns (uint256) {
        vm.prank(account);
        return vault.claim();
    }

    function test_constructorConfiguredWithoutInitializationOrPrivileges() public view {
        assertEq(address(vault.token()), address(token));
        assertEq(vault.totalStaked(), 0);
        assertEq(vault.queuedTips(), 0);
        assertEq(vault.rewardPerShare(), 0);
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(token.totalSupply(), 1e27);
    }

    function test_constructorRejectsMissingTokenAndETH() public {
        vm.expectRevert(TipVault.InvalidToken.selector);
        new TipVault(address(0));
        vm.expectRevert(TipVault.InvalidToken.selector);
        new TipVault(ALICE);
        bytes memory code = abi.encodePacked(type(TipVault).creationCode, abi.encode(address(token)));
        address deployed;
        assembly ("memory-safe") {
            deployed := create(1, add(code, 32), mload(code))
        }
        assertEq(deployed, address(0));
    }

    function test_proRataAcrossMultipleStakersAndPartialClaims() public {
        _stake(ALICE, 1 ether);
        _stake(BOB, 3 ether);
        _stake(CAROL, 6 ether);
        vault.tip{value: 10 ether}();
        assertEq(vault.claimable(ALICE), 1 ether);
        assertEq(vault.claimable(BOB), 3 ether);
        assertEq(vault.claimable(CAROL), 6 ether);
        assertEq(_claim(BOB), 3 ether);
        vault.tip{value: 20 ether}();
        assertEq(vault.claimable(ALICE), 3 ether);
        assertEq(vault.claimable(BOB), 6 ether);
        assertEq(vault.claimable(CAROL), 18 ether);
        assertEq(_claim(ALICE) + _claim(BOB) + _claim(CAROL), 27 ether);
        assertEq(address(vault).balance, 0);
        assertEq(ALICE.balance + BOB.balance + CAROL.balance, 30 ether);
        assertEq(token.balanceOf(address(vault)), 10 ether);
    }

    function test_lateStakerAndIncreasedStakeCannotEarnEarlierTips() public {
        _stake(ALICE, 1 ether);
        vault.tip{value: 4 ether}();
        _stake(BOB, 2 ether);
        _stake(ALICE, 1 ether);
        assertEq(vault.claimable(ALICE), 4 ether);
        assertEq(vault.claimable(BOB), 0);
        vault.tip{value: 8 ether}();
        assertEq(vault.claimable(ALICE), 8 ether);
        assertEq(vault.claimable(BOB), 4 ether);
    }

    function test_partialThenFullUnstakeRetainsRewardsAndPrincipal() public {
        uint256 initial = token.balanceOf(ALICE);
        _stake(ALICE, 4 ether);
        _stake(BOB, 2 ether);
        vault.tip{value: 6 ether}();
        _unstake(ALICE, 2 ether);
        vault.tip{value: 4 ether}();
        _unstake(ALICE, 2 ether);
        vault.tip{value: 2 ether}();
        assertEq(token.balanceOf(ALICE), initial);
        assertEq(vault.stakedOf(ALICE), 0);
        assertEq(vault.totalStaked(), 2 ether);
        assertEq(vault.claimable(ALICE), 6 ether);
        assertEq(vault.claimable(BOB), 6 ether);
        assertEq(_claim(ALICE), 6 ether);
        assertEq(ALICE.balance, 6 ether);
        vm.prank(ALICE);
        vm.expectRevert(TipVault.NoRewards.selector);
        vault.claim();
    }

    function test_exitAndRestakeDoesNotEarnWhileAbsent() public {
        _stake(ALICE, 1 ether);
        _stake(BOB, 1 ether);
        vault.tip{value: 2 ether}();
        _unstake(ALICE, 1 ether);
        vault.tip{value: 3 ether}();
        _stake(ALICE, 1 ether);
        vault.tip{value: 2 ether}();
        assertEq(_claim(ALICE), 2 ether);
        assertEq(_claim(BOB), 5 ether);
    }

    function test_zeroStakeTipsWaitForNextPositiveTipWithStake() public {
        vault.tip{value: 3 ether}();
        (bool ok,) = address(vault).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(vault.queuedTips(), 4 ether);
        _stake(ALICE, 1 ether);
        assertEq(vault.claimable(ALICE), 0);
        assertEq(vault.queuedTips(), 4 ether);
        _stake(BOB, 3 ether);
        vm.prank(ALICE);
        vm.expectRevert(TipVault.NoRewards.selector);
        vault.claim();
        vault.tip{value: 4 ether}();
        assertEq(vault.queuedTips(), 0);
        assertEq(vault.claimable(ALICE), 2 ether);
        assertEq(vault.claimable(BOB), 6 ether);
    }

    function test_queueSurvivesStakeExitWithoutDistributionAndStartsANewEpoch() public {
        _stake(ALICE, 1 ether);
        vault.tip{value: 2 ether}();
        _unstake(ALICE, 1 ether);
        vault.tip{value: 3 ether}();
        _stake(CAROL, 1 ether);
        _unstake(CAROL, 1 ether);
        assertEq(vault.queuedTips(), 3 ether);
        assertEq(_claim(ALICE), 2 ether);
        _stake(BOB, 1 ether);
        (bool ok,) = address(vault).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(vault.claimable(ALICE), 0);
        assertEq(vault.claimable(CAROL), 0);
        assertEq(_claim(BOB), 4 ether);
        assertEq(address(vault).balance, 0);
    }

    function test_zeroAmountsAndExcessWithdrawalRevert() public {
        vm.expectRevert(TipVault.ZeroAmount.selector);
        vault.stake(0);
        vm.expectRevert(TipVault.ZeroAmount.selector);
        vault.unstake(0);
        vm.expectRevert(TipVault.ZeroAmount.selector);
        vault.tip();
        (bool ok,) = address(vault).call("");
        assertFalse(ok);
        vm.expectRevert(TipVault.NoRewards.selector);
        vault.claim();
        _stake(ALICE, 1 ether);
        vm.prank(ALICE);
        vm.expectRevert(TipVault.InsufficientStake.selector);
        vault.unstake(1 ether + 1);
        vm.prank(BOB);
        vm.expectRevert(TipVault.InsufficientStake.selector);
        vault.unstake(1);
        assertEq(vault.totalStaked(), 1 ether);
        assertEq(vault.stakedOf(ALICE), 1 ether);
    }

    function test_failedStakeAllowanceOrBalanceRollsBackAccounting() public {
        _stake(ALICE, 1 ether);
        vault.tip{value: 1 ether}();
        vm.prank(ALICE);
        token.approve(address(vault), 0);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(vault), 0, 1));
        vault.stake(1);
        vm.prank(ALICE);
        token.approve(address(vault), type(uint256).max);
        uint256 balance = token.balanceOf(ALICE);
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, balance + 1)
        );
        vault.stake(balance + 1);
        assertEq(vault.stakedOf(ALICE), 1 ether);
        assertEq(vault.totalStaked(), 1 ether);
        assertEq(vault.claimable(ALICE), 1 ether);
        assertEq(token.balanceOf(address(vault)), 1 ether);
    }

    function test_claimReentrancyFailsWithGuardErrorAndCannotDoublePay() public {
        ClaimRecipient recipient = new ClaimRecipient(vault);
        token.transfer(address(recipient), 1 ether);
        recipient.deposit(1 ether);
        _stake(ALICE, 1 ether);
        vault.tip{value: 4 ether}();
        recipient.configure(false, true, abi.encodeCall(TipVault.claim, ()));
        recipient.withdrawReward();
        assertFalse(recipient.attackSucceeded());
        assertEq(
            recipient.attackResult(), abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector)
        );
        assertEq(recipient.claimableDuringCallback(), 0);
        assertEq(recipient.received(), 2 ether);
        assertEq(vault.claimable(address(recipient)), 0);
        assertEq(vault.claimable(ALICE), 2 ether);
        assertEq(address(vault).balance, 2 ether);
        assertEq(_claim(ALICE), 2 ether);
    }

    function test_claimCallbackCannotReenterOtherStateChangingFunctions() public {
        ClaimRecipient recipient = new ClaimRecipient(vault);
        token.transfer(address(recipient), 2 ether);
        recipient.deposit(1 ether);
        bytes[4] memory calls = [
            abi.encodeCall(TipVault.stake, (1)),
            abi.encodeCall(TipVault.unstake, (1)),
            abi.encodeCall(TipVault.tip, ()),
            bytes("")
        ];
        for (uint256 i; i < calls.length; ++i) {
            vault.tip{value: 1 ether}();
            recipient.configure(false, true, calls[i]);
            recipient.withdrawReward();
            assertFalse(recipient.attackSucceeded());
            assertEq(
                recipient.attackResult(), abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector)
            );
            assertEq(vault.stakedOf(address(recipient)), 1 ether);
            assertEq(vault.totalStaked(), 1 ether);
        }
        assertEq(recipient.received(), 4 ether);
    }

    function test_rejectedClaimPreservesRewardsAndDoesNotBlockUnstakingOrOthers() public {
        ClaimRecipient recipient = new ClaimRecipient(vault);
        token.transfer(address(recipient), 1 ether);
        recipient.deposit(1 ether);
        _stake(ALICE, 1 ether);
        vault.tip{value: 4 ether}();
        recipient.configure(true, false, "");
        vm.expectRevert(TipVault.ETHTransferFailed.selector);
        recipient.withdrawReward();
        assertEq(vault.claimable(address(recipient)), 2 ether);
        assertEq(address(vault).balance, 4 ether);
        recipient.withdrawStake(1 ether);
        assertEq(token.balanceOf(address(recipient)), 1 ether);
        assertEq(_claim(ALICE), 2 ether);
        recipient.configure(false, false, "");
        recipient.withdrawReward();
        assertEq(recipient.received(), 2 ether);
        assertEq(address(vault).balance, 0);
    }

    function test_fractionalRewardsSurviveCheckpointsClaimsAndFullExit() public {
        _stake(ALICE, 1);
        _stake(BOB, 1);
        vault.tip{value: 1}();
        assertEq(vault.claimable(ALICE), 0);
        _unstake(ALICE, 1);
        _stake(ALICE, 1);
        vault.tip{value: 1}();
        assertEq(_claim(ALICE), 1);
        assertEq(_claim(BOB), 1);
        vault.tip{value: 3}();
        assertEq(_claim(ALICE), 1);
        _unstake(ALICE, 1);
        _stake(ALICE, 1);
        vault.tip{value: 1}();
        assertEq(_claim(ALICE), 1);
        assertEq(_claim(BOB), 2);
        assertEq(address(vault).balance, 0);
    }

    function test_roundingNeverCreditsOldActiveStakeDustToLateStaker() public {
        _stake(ALICE, 3 ether);
        vault.tip{value: 1}();
        assertEq(vault.rewardPerShare(), 0);
        _unstake(ALICE, 3 ether);
        _stake(BOB, 1 ether);
        vault.tip{value: 1}();
        assertEq(vault.claimable(ALICE), 0);
        assertEq(_claim(BOB), 1);
        assertEq(address(vault).balance, 1);
        assertEq(vault.queuedTips(), 0);
    }

    function test_directTokenAndForcedETHSurplusDoNotCreateRewardsOrStake() public {
        _stake(ALICE, 1 ether);
        token.transfer(address(vault), 5 ether);
        // Models ETH delivered without executing receive (e.g. forced ETH).
        vm.deal(address(vault), 7 ether);
        assertEq(vault.totalStaked(), 1 ether);
        assertEq(vault.claimable(ALICE), 0);
        vault.tip{value: 1 ether}();
        assertEq(_claim(ALICE), 1 ether);
        _unstake(ALICE, 1 ether);
        assertEq(token.balanceOf(address(vault)), 5 ether);
        assertEq(address(vault).balance, 7 ether);
    }

    function test_eventsDescribeStakeUnstakeQueuedTipDistributionAndClaim() public {
        vm.expectEmit(true, false, false, true, address(vault));
        emit Tipped(address(this), 1 ether, 0);
        vault.tip{value: 1 ether}();
        vm.expectEmit(true, false, false, true, address(vault));
        emit Staked(ALICE, 2 ether);
        _stake(ALICE, 2 ether);
        vm.expectEmit(true, false, false, true, address(vault));
        emit Tipped(address(this), 1 ether, 2 ether);
        (bool ok,) = address(vault).call{value: 1 ether}("");
        assertTrue(ok);
        vm.expectEmit(true, false, false, true, address(vault));
        emit Unstaked(ALICE, 2 ether);
        _unstake(ALICE, 2 ether);
        vm.expectEmit(true, false, false, true, address(vault));
        emit Claimed(ALICE, 2 ether);
        _claim(ALICE);
    }

    function test_noAdminSelectorsOrUnknownFallback() public {
        string[6] memory calls = [
            "initialize(address)",
            "transferOwnership(address)",
            "setToken(address)",
            "pause()",
            "withdrawETH(address,uint256)",
            "rescueTokens(address,uint256)"
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool ok,) = address(vault).call(abi.encodeWithSignature(calls[i], ALICE, 1));
            assertFalse(ok);
        }
    }
}
