# Deployment and review handoff

This source contribution is for the Tip Jar test launch on **Sepolia, chain ID
11155111**. No deployment transaction is executed by these files.

| Order | Identifier | Foundry artifact | Constructor arguments | Constructor ETH |
| --- | --- | --- | --- | --- |
| Token | `TipJarToken` | `src/TipJarToken.sol:TipJarToken` | `[]` | 0 |
| Application 1 | `TipVault` | `src/TipVault.sol:TipVault` | `["$token"]` | 0 |

The application constructor is exactly one ABI-encoded address word. `$token` must
resolve to the preceding deployed launch token. The vault checks that the address
has code, so the token must already exist. Neither contract requires initialization,
constructor funding, owner parameters, a privileged address, or an application call
after creation. Deploying the token through ProjectFactory puts all `10^27` minor
units in the factory's balance, regardless of transaction origin. Constructing the
vault neither transfers nor approves any factory-held tokens.

There is one application contract. Both names fit the manifest identifier constraint;
neither uses the reserved `MerkleDistributor` name. Both constructors are nonpayable,
and the application has no proxy or upgrade route. Build settings and vendored imports
must remain identical between compilation, review, and source attestation.

## Assigned responsibilities

- **Source contributor:** contracts, unit/fuzz tests, interface exports, and this
  handoff. The source contribution does not create `launch.json`.
- **Manifest contributor:** generate `launch.json` describing the accepted artifacts,
  one application in dependency order, and the exact `$token` constructor reference.
- **Independent reviewer:** inspect accepted source, tests, and the actual generated
  manifest. Review token supply, absence of privileges, constructor linkage, custody,
  queued tips, dust, reward checkpoints, ETH rejection, and adversarial callbacks.
  Local passing tests are evidence, not an independent audit or release approval.
- **Services/control plane:** publish source, bind signed artifacts and pinned policy,
  freeze allocations, attest, admit, deploy, and verify actual addresses and artifacts.
  Policy linkage and signatures belong to these services. Concrete mismatches between
  source, constructor arguments, policy, or authorization must be reported for review.
- **Frontend contributor after deployment:** consume actual deployment handoff addresses
  and ABIs, verify the handoff's canonical ABI hashes, and implement the approved plain
  Sepolia UI. No addresses, ABI hash scheme, or wallet credentials are invented here.

The approved policy context is Sepolia v5: 2% to this launch's accepted contributors,
8% equally to unique accepted-work wallets from the prior 12 hours (overlap combined),
80% LP, 10% treasury, one-hour unlock. The native ETH pool has fee 3000, tick spacing
60, and policy-derived **20 ETH opening FDV** for the full billion-token supply.
The provenance `initialPrice` is `79228162514264337593543950336`; policy overrides it
with the effective opening price. Liquidity is token-only, with no ETH seed funding.
These values describe the supplied brief; contracts do not select recipients, enforce
launch allocation policy, or derive pool prices.

No unresolved owner or constructor parameter remains. Actual factory, token, vault,
pool addresses, signed artifacts, and deployment receipts are later service outputs.
Independent manifest review and those outputs are not prerequisites for this bounded
implementation assignment. No mainnet operation is part of this launch.
