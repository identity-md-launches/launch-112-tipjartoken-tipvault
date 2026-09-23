// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TipVault} from "../src/TipVault.sol";

contract FailingToken is ERC20 {
    bool public fail;

    constructor() ERC20("Fixture", "FIX") {
        _mint(msg.sender, 100 ether);
    }

    function setFail(bool value) external {
        fail = value;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (fail) return false;
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (fail) return false;
        return super.transferFrom(from, to, amount);
    }
}

contract NoReturnToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor() {
        balanceOf[msg.sender] = 100 ether;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function transfer(address to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 amount) external {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

contract SafeTransfersTest is Test {
    function test_falseTransferFromCannotCreateStake() public {
        FailingToken token = new FailingToken();
        TipVault vault = new TipVault(address(token));
        token.approve(address(vault), 100 ether);
        token.setFail(true);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        vault.stake(1 ether);
        assertEq(vault.totalStaked(), 0);
        assertEq(vault.stakedOf(address(this)), 0);
        assertEq(token.balanceOf(address(vault)), 0);
    }

    function test_falseTransferCannotDestroyPrincipalOrRewards() public {
        FailingToken token = new FailingToken();
        TipVault vault = new TipVault(address(token));
        token.approve(address(vault), 100 ether);
        vault.stake(1 ether);
        vm.deal(address(this), 1 ether);
        vault.tip{value: 1 ether}();
        token.setFail(true);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        vault.unstake(1 ether);
        assertEq(vault.totalStaked(), 1 ether);
        assertEq(vault.stakedOf(address(this)), 1 ether);
        assertEq(vault.claimable(address(this)), 1 ether);
        assertEq(token.balanceOf(address(vault)), 1 ether);
        token.setFail(false);
        vault.unstake(1 ether);
        assertEq(token.balanceOf(address(this)), 100 ether);
        assertEq(vault.claim(), 1 ether);
    }

    function test_optionalReturnTokenTransfersSucceed() public {
        NoReturnToken token = new NoReturnToken();
        TipVault vault = new TipVault(address(token));
        token.approve(address(vault), 3 ether);
        vault.stake(3 ether);
        assertEq(vault.totalStaked(), 3 ether);
        assertEq(token.balanceOf(address(vault)), 3 ether);
        vault.unstake(3 ether);
        assertEq(vault.totalStaked(), 0);
        assertEq(token.balanceOf(address(this)), 100 ether);
    }

    receive() external payable {}
}
