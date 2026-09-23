// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TipJarToken} from "../src/TipJarToken.sol";
import {TipVault} from "../src/TipVault.sol";

contract TipVaultFuzzTest is Test {
    uint256 private constant SCALE = 1e18;
    TipJarToken private token;
    TipVault private vault;
    address[3] private actors = [address(0xA11CE), address(0xB0B), address(0xCA401)];

    // An eager ledger credits every actor on each distribution. It has no user checkpoints or lazy accrual.
    struct Ledger {
        uint256[3] stakes;
        uint256[3] scaledRewards;
        uint256 total;
        uint256 queue;
        uint256 tipped;
        uint256 paid;
        uint256 scaledDust;
    }

    function setUp() public {
        token = new TipJarToken();
        vault = new TipVault(address(token));
        for (uint256 i; i < actors.length; ++i) {
            token.transfer(actors[i], 1_000_000 ether);
            vm.prank(actors[i]);
            token.approve(address(vault), type(uint256).max);
        }
        vm.deal(address(this), 1_000_000 ether);
    }

    function testFuzz_roundingDustBounded(uint96 a, uint96 b, uint96 c, uint96 amount) public {
        uint256[3] memory stakes = [bound(a, 1, 1e24), bound(b, 1, 1e24), bound(c, 1, 1e24)];
        uint256 total = stakes[0] + stakes[1] + stakes[2];
        uint256 tipAmount = bound(amount, 1, 100 ether);
        for (uint256 i; i < actors.length; ++i) {
            vm.prank(actors[i]);
            vault.stake(stakes[i]);
        }
        vault.tip{value: tipAmount}();
        uint256 claims;
        for (uint256 i; i < actors.length; ++i) {
            uint256 claimable = vault.claimable(actors[i]);
            assertLe(claimable, tipAmount * stakes[i] / total, "exceeds ideal pro-rata entitlement");
            claims += claimable;
            if (claimable > 0) {
                vm.prank(actors[i]);
                assertEq(vault.claim(), claimable);
            }
        }
        uint256 dust = tipAmount - claims;
        assertEq(address(vault).balance, dust);
        // Distribution loses < total / SCALE wei; each actor retains < 1 whole wei as a fraction.
        assertLt(dust * SCALE, total + actors.length * SCALE);
    }

    function test_fullSupplyPrecisionBoundaryIsBounded() public {
        token.transfer(actors[0], token.balanceOf(address(this)));
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            vm.prank(actors[i]);
            vault.stake(balance);
        }
        assertEq(vault.totalStaked(), 1e27);
        vault.tip{value: 999_999_999}();
        assertEq(vault.rewardPerShare(), 0);
        vault.tip{value: 1_000_000_001}();
        assertEq(vault.rewardPerShare(), 1);
        uint256 totalClaimable;
        for (uint256 i; i < actors.length; ++i) {
            totalClaimable += vault.claimable(actors[i]);
        }
        assertEq(totalClaimable, 1_000_000_000);
        assertEq(address(vault).balance - totalClaimable, 1_000_000_000);
    }

    function testFuzz_stakeUnstakeTipClaimSequencesPreserveSolvency(uint256 seed) public {
        Ledger memory ledger;
        for (uint256 step; step < 96; ++step) {
            seed = uint256(keccak256(abi.encode(seed, step)));
            uint256 who = (seed >> 8) % actors.length;
            uint256 action = seed % 6;
            uint256 value = seed >> 32;
            if (action == 0) {
                uint256 amount = value % (1000 ether) + 1;
                vm.prank(actors[who]);
                vault.stake(amount);
                ledger.stakes[who] += amount;
                ledger.total += amount;
            } else if (action == 1 || action == 5) {
                if (ledger.stakes[who] > 0) {
                    uint256 amount = action == 5 ? ledger.stakes[who] : value % ledger.stakes[who] + 1;
                    vm.prank(actors[who]);
                    vault.unstake(amount);
                    ledger.stakes[who] -= amount;
                    ledger.total -= amount;
                }
            } else if (action == 2 || action == 4) {
                _tipAndCredit(ledger, value % (10 ether) + 1, action == 4);
            } else {
                _claimAndDebit(ledger, who);
            }
            _checkLedger(ledger);
        }
        // All principals remain redeemable, and all whole-wei rewards survive complete exit.
        for (uint256 i; i < actors.length; ++i) {
            if (ledger.stakes[i] > 0) {
                vm.prank(actors[i]);
                vault.unstake(ledger.stakes[i]);
                ledger.total -= ledger.stakes[i];
                ledger.stakes[i] = 0;
            }
            _claimAndDebit(ledger, i);
            assertEq(token.balanceOf(actors[i]), 1_000_000 ether);
            _checkLedger(ledger);
        }
    }

    function _tipAndCredit(Ledger memory ledger, uint256 amount, bool plainReceive) private {
        if (plainReceive) {
            (bool ok,) = address(vault).call{value: amount}("");
            assertTrue(ok);
        } else {
            vault.tip{value: amount}();
        }
        ledger.tipped += amount;
        if (ledger.total == 0) {
            ledger.queue += amount;
        } else {
            uint256 scaledDistribution = (amount + ledger.queue) * SCALE;
            ledger.queue = 0;
            uint256 allocated;
            for (uint256 i; i < actors.length; ++i) {
                uint256 share = (scaledDistribution / ledger.total) * ledger.stakes[i];
                ledger.scaledRewards[i] += share;
                allocated += share;
            }
            ledger.scaledDust += scaledDistribution - allocated;
        }
    }

    function _claimAndDebit(Ledger memory ledger, uint256 who) private {
        uint256 amount = ledger.scaledRewards[who] / SCALE;
        vm.prank(actors[who]);
        if (amount == 0) {
            vm.expectRevert(TipVault.NoRewards.selector);
            vault.claim();
        } else {
            assertEq(vault.claim(), amount);
            ledger.scaledRewards[who] -= amount * SCALE;
            ledger.paid += amount;
        }
    }

    function _checkLedger(Ledger memory ledger) private view {
        uint256 claims;
        uint256 scaledRewards;
        for (uint256 i; i < actors.length; ++i) {
            uint256 claimable = vault.claimable(actors[i]);
            assertEq(claimable, ledger.scaledRewards[i] / SCALE, "lazy accounting disagrees with eager ledger");
            assertEq(vault.stakedOf(actors[i]), ledger.stakes[i]);
            claims += claimable;
            scaledRewards += ledger.scaledRewards[i];
        }
        assertGe(address(vault).balance, claims + ledger.queue, "ETH insolvency");
        assertEq(address(vault).balance + ledger.paid, ledger.tipped, "ETH conservation");
        assertEq(address(vault).balance * SCALE, scaledRewards + ledger.queue * SCALE + ledger.scaledDust);
        assertEq(vault.totalStaked(), ledger.total);
        assertEq(vault.queuedTips(), ledger.queue);
        assertEq(token.balanceOf(address(vault)), ledger.total, "principal conservation");
        assertEq(token.totalSupply(), 1e27);
    }
}
