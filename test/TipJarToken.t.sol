// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TipJarToken} from "../src/TipJarToken.sol";

contract TokenFactoryFixture {
    function deploy() external returns (TipJarToken) {
        return new TipJarToken();
    }
}

contract TipJarTokenTest is Test {
    TipJarToken private token;
    uint256 private constant SUPPLY = 1e27;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    function setUp() public {
        token = new TipJarToken();
    }

    function test_metadataAndFixedSupply() public view {
        assertEq(token.name(), "Tip Jar");
        assertEq(token.symbol(), "TIPS");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_factoryGetsSupplyInsteadOfOrigin() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        vm.prank(ALICE, ALICE);
        TipJarToken deployed = factory.deploy();
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(ALICE), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    function testFuzz_transferConservesSupply(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveAndTransferFromSpendExactAllowance() public {
        token.transfer(ALICE, 20 ether);
        vm.prank(ALICE);
        assertTrue(token.approve(BOB, 12 ether));
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, BOB, 7 ether));
        assertEq(token.allowance(ALICE, BOB), 5 ether);
        assertEq(token.balanceOf(ALICE), 13 ether);
        assertEq(token.balanceOf(BOB), 7 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFailuresLeaveBalancesUnchanged() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        token.transfer(BOB, 1);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_commonAdminAndMintSelectorsUnavailableToAnyoneIncludingDeployer() public {
        string[12] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)",
            "setTax(uint256)",
            "blacklist(address)"
        ];
        for (uint256 caller; caller < 2; ++caller) {
            for (uint256 i; i < signatures.length; ++i) {
                vm.prank(caller == 0 ? ALICE : address(this));
                (bool ok,) = address(token).call(abi.encodeWithSignature(signatures[i], ALICE, 1 ether));
                assertFalse(ok, signatures[i]);
                assertEq(token.totalSupply(), SUPPLY);
                assertEq(token.balanceOf(ALICE), 0);
            }
        }
    }

    function test_constructorAndRuntimeRejectETH() public {
        vm.deal(address(this), 1 ether);
        bytes memory code = type(TipJarToken).creationCode;
        address deployed;
        assembly ("memory-safe") {
            deployed := create(1, add(code, 32), mload(code))
        }
        assertEq(deployed, address(0));
        (bool ok,) = address(token).call{value: 1}("");
        assertFalse(ok);
    }
}
