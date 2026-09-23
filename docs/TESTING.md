# Local verification

The delivered suite is self-contained, using the real TipJarToken for reward and
principal tests, plus small test-only contracts for rejecting receivers and unusual
ERC-20 return values. It does not fork a chain, use a deployed wallet, or broadcast.

| Suite | Evidence |
| --- | --- |
| `test/TipJarToken.t.sol` | Exact metadata and fixed supply; factory versus origin; fuzzed fee-free transfers; approvals; insufficient balance/allowance; zero receiver; unavailable common admin selectors for deployer and stranger; nonpayable deployment/runtime |
| `test/TipVault.t.sol` | Constructor validation; multiple-staker splits; late/increased stake; partial/full exits and later claims; restaking; both tip routes; zero-stake queues over multiple epochs; invalid operations; failed stake rollback; events; surplus assets |
| `test/TipVault.t.sol` receiver fixtures | Exact guard error on nested claim and other state-changing callbacks; credit cleared during payout; single payment only; rejected payout restores rewards; other users can claim and rejecting receiver can unstake |
| `test/SafeTransfers.t.sol` | False-return transferFrom cannot create stake; failed transfer cannot destroy principal or reward credit; no-return transfers succeed through SafeERC20 |
| `test/TipVaultFuzz.t.sol` | Random amounts and stake ratios bound rounding loss; full-supply precision boundary; randomized stake/partial-exit/full-exit/tip/receive/claim sequences compare against an eager per-user ledger |

The sequence fuzz test runs **256 seeds with 96 operations each** over three users,
then exits every stake and collects every whole-wei claim. After every operation it
checks actual claimables against the ledger, ETH balance at least sum of claimables
plus queued tips, ETH conservation, exact scaled entitlement-plus-dust conservation,
principal conservation, total stakes, and fixed token supply. The reference ledger
credits each user on every tip instead of reproducing the vault's lazy checkpoints.

`foundry.toml` pins the default fuzz seed and 256 runs for each of the three fuzz tests.
To explore an additional reproducible seed, use `forge test --fuzz-seed <hex-seed>`.

The supplied protected deployment checks are a separate floor: constructor execution,
factory supply preservation, decimals, transfers, runtime size, and forbidden opcode
scans. They do not prove arbitrary application correctness. Their environment and
source are supplied by the verifier, not dependencies of the delivered suite.

## Recorded results (2026-09-23)

With Forge 1.8.3 and Solidity 0.8.26, a clean offline rebuild completed successfully:

- `forge clean && forge build`: passed; 45 Solidity source files compiled.
- `forge test`: **31 passed, 0 failed, 0 skipped**, including three fuzz tests with
  256 runs apiece and the 96-operation sequence test.
- `forge fmt --check`: passed.
- `python3 scripts/export_abis.py --check`: both ABI exports matched the fresh build.
- Vendored source SHA-256 checks: all files matched `dependencies.lock.json`.
- Supplied protected checks: **8 passed, 0 failed, 0 skipped**, using temporary copies
  in `test/scratch`, compiled creation bytecode, locally predicted CREATE2 addresses,
  the specified supply/decimals, and `TipVault(token)` constructor data. This local
  fixture did not use or validate a generated launch manifest or a live factory.
- Runtime sizes: TipJarToken **1,722 bytes**; TipVault **2,581 bytes**. Both passed
  the supplied opcode scans and the application runtime size check. Constructor ABIs
  were checked as nonpayable, with zero token arguments and one vault address argument.

Forge's heuristic linter emits `reentrancy-events` warnings at the vault events and
`reentrancy-eth` at its payout call. These warnings are retained for reviewer visibility.
All externally callable vault mutations use OpenZeppelin's shared guard; stake and
unstake events precede token interaction, and claim clears credit and emits before
payment. Callback tests verify the exact guard error, single payout, and rollback on
rejected ETH. These observations do not replace independent adversarial review.

Limitations: fuzzing explores finite sequences and does not prove all states. The
SafeERC20 fixtures test return handling, not support for fee-on-transfer or rebasing
assets. Forced ETH is modeled with a local balance cheatcode. No production chain,
actual launch manifest, policy signature, deployment, or frontend behavior is claimed
to have been tested by this source assignment.
