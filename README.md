# Tip Jar

Tip Jar is a Sepolia test launch: stake TIPS, anyone can tip ETH, stakers share tips.
This repository delivers the contracts, local tests, ABI exports, and deployment handoff.

| Contract | Source | Constructor | Behavior |
| --- | --- | --- | --- |
| TipJarToken | `src/TipJarToken.sol` | `()` nonpayable | ERC-20 named `Tip Jar`, symbol `TIPS`, 18 decimals; exactly `10^27` minor units minted to `msg.sender` once |
| TipVault | `src/TipVault.sol` | `(address token_)` nonpayable | Immutable token custody and pull-based pro-rata ETH rewards |

Both contracts are adminless and immutable. There is no owner, initializer, upgrade,
mint entry point, fee, tax, blacklist, pause, emissions, or rescue function. The token
uses OpenZeppelin ERC20; the vault uses SafeERC20, ReentrancyGuard, and Math.

## Offline build and checks

Prerequisites: Foundry and native Solidity **0.8.26** already installed in Foundry's
compiler cache. The checked toolchain is Forge **1.8.3**. `foundry.toml` pins Solidity
0.8.26, Cancun, optimizer 200 runs, and `bytecode_hash = "none"`. Offline mode is
enabled by default. No RPC, package installation, FFI, filesystem cheatcode permission,
environment variable, wallet, or key is required by the delivered tests.

```sh
forge build
forge test
forge fmt --check
python3 scripts/export_abis.py --check
```

OpenZeppelin Contracts **v5.1.0** and forge-std **v1.9.4** are vendored as ordinary
source files under `lib/`, including licenses. Only OpenZeppelin's required import
closure and forge-std's Solidity sources are included. Exact upstream URLs, archive
SHA-256 digests, and per-file digests are in `docs/dependencies.lock.json`. There are
no submodules or remotely resolved Solidity dependencies. The installed toolchain
is a prerequisite; no compiler executable or wrapper is configured in the repository.

Regenerate the ABI exports after changing either contract:

```sh
python3 scripts/export_abis.py
```

## Vault accounting and rounding

`stake(amount)` pulls approved TIPS and `unstake(amount)` returns the caller's principal.
Both require a positive amount and checkpoint existing rewards before changing stake.
Unstaking never forces an ETH claim, so even an address that rejects ETH can recover
its tokens. An account can claim after fully exiting and can restake later.

`tip()` and plain ETH transfers to `receive()` have identical behavior and require a
positive value. With active stake `S`, a tip of `D` wei increases the global index by
`floor(D * 10^18 / S)`. Pending rewards follow each account's stake during each index
interval. New stake gets the current checkpoint and cannot earn earlier active-stake
tips. Fractional per-account rewards remain with that account across stake changes,
claims, and full exits; whole-wei rewards are available from `claimable(account)`.

**Zero-stake choice:** tips received when `totalStaked == 0` accumulate in `queuedTips`.
Staking, unstaking, and claiming do not distribute the queue. The next **positive tip
or receive with active stake** distributes its own value plus the entire queue among
the stakes present at that moment. Any number of accounts can join or leave before
that trigger. If no such tip arrives, the queue remains held indefinitely. There is
no sender refund. This rule also applies after all previous stakers exit.

**Dust bound:** for a distribution with `S` minor units staked, index rounding leaves
strictly less than `S / 10^18` wei unallocated. For `N` distributions and `A` accounts
that have participated, the balance not presently claimable or queued is strictly
less than `sum(S_i / 10^18) + A` wei (absent forced ETH). Each account's extra fraction
is less than one wei and remains attributable to it. With this token's fixed supply,
global rounding loses less than **10^9 wei per distribution**. At full-supply stake,
a tip smaller than 10^9 wei can be entirely dust. Global rounding dust stays in the
vault permanently; it is never recycled into a later staker's rewards. This preserves
the rule against earning earlier tips. No admin can sweep dust.

`claim()` checkpoints, clears the caller's whole-wei credit, emits its event, and
then sends ETH to that caller. A failed send reverts the credit change and the event.
All state-changing entry points share the reentrancy guard. Read-only `claimable`
already reflects a cleared credit during the receiver callback.

## Assumptions and operations

The constructor must reference this launch's TipJarToken. It rejects zero addresses
and addresses without code; that check is not token authentication. Fee-on-transfer,
rebasing, or malicious replacement tokens are outside the accounting assumptions.
Clients must use 18-decimal token units, approve the vault (preferably the exact stake
amount), then stake. ETH amounts and returned rewards are wei. Wallet contracts need
a payable receiver to claim; the vault has no claim-to-another-address mechanism.

Direct ERC-20 transfers to the vault create no stake. ETH forced into the vault without
executing `tip`/`receive` creates no reward. Such surplus assets cannot be recovered.
There is no minimum holding time or time weighting: a stake present at a tip receives
its share even if it arrived immediately beforehand. Public tips and queued tips may
therefore attract temporary stakes or transaction ordering strategies. This is the
approved current-stake design, with no yield guarantee or custody administrator.

See [the ABI reference](docs/ABI.md), [test coverage](docs/TESTING.md), and
[deployment responsibilities](docs/DEPLOYMENT.md). Independent adversarial review of
the accepted source and generated manifest remains a separate release step.
