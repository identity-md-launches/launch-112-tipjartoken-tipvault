# Contract interfaces

The complete machine-readable ABIs are generated from the compiled implementation:
[TipJarToken](abi/TipJarToken.json) and [TipVault](abi/TipVault.json).
`python3 scripts/export_abis.py --check` verifies that the exports match a fresh build.
These are interface artifacts, not deployment addresses or signed attestations.

TipJarToken exposes standard ERC-20 `name`, `symbol`, `decimals`, `totalSupply`,
`balanceOf`, `allowance`, `approve`, `transfer`, and `transferFrom`, together with
`Transfer` and `Approval` events and OpenZeppelin ERC-20 errors. There are no constructor
arguments and no public mint or burn methods.

## TipVault

| Entry point | Mutability / result | Semantics |
| --- | --- | --- |
| `constructor(address token_)` | nonpayable | One static address word; bind the launch token once |
| `stake(uint256 amount)` | nonpayable | Pull approved tokens from caller; positive amount |
| `unstake(uint256 amount)` | nonpayable | Return caller's principal; positive and at most caller's stake |
| `tip()` | payable | Donate positive ETH, distribute or queue |
| `receive()` | payable | Same behavior as `tip`, for empty calldata |
| `claim()` | nonpayable, returns `uint256 amount` | Send all whole-wei rewards to caller; revert if none or payment fails |
| `token()` | view, `address` | Immutable staking asset |
| `totalStaked()` | view, `uint256` | Total accounted token principal in minor units |
| `stakedOf(address account)` | view, `uint256` | Account's principal in minor units |
| `claimable(address account)` | view, `uint256` | ETH immediately claimable in whole wei |
| `queuedTips()` | view, `uint256` | Zero-stake tips awaiting a positive staker-bearing tip |
| `rewardPerShare()` | view, `uint256` | Cumulative index, scaled by `10^18` |
| `REWARD_SCALE()` | view, `uint256` | Constant `10^18` |

There is no fallback for unknown selectors. Only `tip` and `receive` accept ETH.

| Event | Meaning |
| --- | --- |
| `Staked(address indexed account, uint256 amount)` | Account added token principal |
| `Unstaked(address indexed account, uint256 amount)` | Account removed token principal |
| `Tipped(address indexed sender, uint256 amount, uint256 distributed)` | Newly received wei; `distributed` is zero if queued, otherwise the new amount plus previous queue, before rounding |
| `Claimed(address indexed account, uint256 amount)` | Whole wei successfully paid; failed transactions roll this event back |

Vault-defined errors are `InvalidToken`, `ZeroAmount`, `InsufficientStake`, `NoRewards`,
and `ETHTransferFailed`. OpenZeppelin's `ReentrancyGuardReentrantCall` and SafeERC20
errors may also occur. Token calls can bubble ERC-20 errors, including insufficient
allowance/balance. Consumers should handle any reverted transaction as a failed action
and re-read balances after confirmed receipts.
