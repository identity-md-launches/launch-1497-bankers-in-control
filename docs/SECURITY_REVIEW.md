# Builder security review

Scope: `LaunchToken`, `CharterClaim`, and their vendored runtime dependencies. This is a local implementation review, not an independent audit or validation of live chain state.

## Reviewed properties

| Property | Implementation and evidence |
| --- | --- |
| Fixed supply | LaunchToken only mints `10^27` minor units in its constructor. ERC20 exposes no external mint/burn/admin paths. Token tests verify metadata, allowance spending, exact transfers, failures, and unchanged supply. |
| Factory compatibility | Both constructors perform no external calls. Application deployment leaves all supply at the factory. Deployment tests exercise empty-code dependencies and the 10/10/80 allocation model. |
| Initial authorization | Each ID is range-checked, has no claimant, and belongs to `msg.sender`. Tests cover wrong owners, approved operators, transfer before/after initial claims, missing IDs, and boundary IDs. |
| Permanent beneficiary | The only claimant write occurs during the first successful claim. Transfers, burns, remints, and later claim attempts cannot replace it. |
| REST eligibility | Collection-wide balance must be zero. Only the recorded claimant can receive unpaid REST. Tests exercise retained and newly acquired NFTs above the cutoff, revocation/burn, and reacquisition between partial payments. |
| Batch atomicity | Every ID's state changes before one aggregate transfer. Duplicate, mixed-owner, mixed-claimant, invalid, and underfunded batches revert. Later retries remain valid. |
| Reentrancy | OpenZeppelin ReentrancyGuard protects both claim entry points. Callback tests inspect all recorded effects and attempt both same-function and cross-function reentry from a token that is itself the eligible claimant. Both fail with the guard error. |
| Payout failure | SafeERC20 propagates reverts and rejects false/malformed return data. Both phases are tested, including rollback after the test token changed its balances. No-return transfers are tested. A token address without code fails on payment. |
| Dependency failure | No NFT code cannot authorize payouts; a reverted collection balance read blocks REST. A reverted owner read prevents that initial claim and is skipped by the informational aggregate view. |
| Conservation | Full-range test pays exactly `1032 * SHARE` and leaves 200 minor units. The stateful model verifies beneficiaries, single payment flags, actor balances, total supply, and `remaining + paid = allocation + donations`. |
| No asset escape | The only state-changing ABI functions in CharterClaim are `claim` and `claimRest`. There is no approval, administrative, arbitrary-call, or recovery path. Tests probe common unwanted selectors and scan runtime opcodes, skipping PUSH data. |

The contracts use checked Solidity arithmetic. Share division rounds down once; REST receives the per-share remainder after INSTANT. There is no accumulator that redistributes rounding or increases a per-ID allocation following a donation. All production library calls are internal and inlined, so there are no external library link placeholders.

The fixed address is called through view functions, so NFT eligibility reads compile to STATICCALL. The ERC20 transfer is the only state-changing external interaction; all payment state is settled first. The guard additionally excludes callbacks across the two payment functions.

## Deliberate limits

- The application trusts the supplied Founding Charter address and its ERC-721 ownership/balance semantics. There was no live-chain fork or RPC verification in these tests. The local NFT model simulates transfers, burns, and revocations; it cannot establish the deployed NFT's implementation or governance behavior.
- A balance of zero is required at the moment of REST execution. This allows later reacquisition and can be blocked by an unsolicited NFT. These follow directly from the requested wallet-based condition.
- `claimable` catches `ownerOf` failures because nonexistent IDs must be skipped. It cannot distinguish an unminted ID from a temporarily broken owner read, so such a failure can under-report INSTANT. `balanceOf` failures are never interpreted as a zero balance.
- The fixed-supply LaunchToken is the production asset. No token balance-delta checks attempt to support rebasing, taxed, or dishonest replacements. A wrong immutable token argument cannot be repaired.
- The launch system must enforce the requested atomic funding and allocation. The local deployment model is not a copy of, or test against, its actual factory. Constructors intentionally neither move its funds nor validate external contracts.
- The full-range test's setup and multiple operations exceed ordinary transaction gas budgets when summed. Users should estimate gas and split claim batches. The bounded aggregate view may need a sufficiently high RPC call gas limit.
- There is no recovery or upgrade. Unclaimed funds, rounding dust, donations, and accidental assets remain permanently locked. Loss of a claimant's wallet does not permit reassignment.

## Verification

Local tooling: Foundry 1.8.3 with Solidity 0.8.26. The project includes 52 unit/fuzz tests and one stateful invariant test, with 256 cases per fuzz test and 128 invariant runs of 64 actions by default. No test depends on an RPC, environment variable, signing key, execution order, or external dependency download.

Required checks: `forge build`, `forge test`, and `forge fmt --check`. The builder also checks a clean build/test with an empty process environment and parallel test execution. Foundry's lint diagnostics about calls and reverts inside loops correspond to the specified per-ID authorization/atomic rejection; its balance-equality diagnostics correspond to the expressly required zero-NFT balance check.

Slither, Mythril, live deployment, and explorer verification were not run. An independent contributor should review the source and final manifest, including the real token argument and CharterClaim funding recipient, before release.
