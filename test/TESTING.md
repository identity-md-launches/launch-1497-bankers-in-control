# CharterClaim test coverage

Run the offline suite from the repository root with `forge build` and `forge test`.
The existing vendored libraries are sufficient; no RPC, environment writes, downloads,
or additional dependencies are needed. Run counts are set in the Solidity tests.

## Additional properties

`CharterClaimProperties.t.sol` runs each fuzz property 1,000 times:

- Partitioning and permuting a unique batch preserves payouts, rounding, and terminal
  claim records. The comparison starts both executions from the same state and also
  checks the independent per-ID allocation.
- A duplicate at any later position rolls back the entire instant or rest batch;
  retrying the original unique batch succeeds.
- An invalid, missing, burned, foreign-owned, or previously claimed member cannot
  consume other IDs' instant allocations. Invalid, unclaimed, foreign-claimed, and
  already-paid rest members likewise leave all other entitlements usable.
- Sending an instant payout to someone else or returning it to CharterClaim does not
  transfer, replenish, or increase either phase's entitlement.

Deterministic cases distinguish a contract wallet from `tx.origin`, cover reissuance
before the original claimant takes rest, and verify that the initial claim depends
on NFT ownership without introducing a balance-read dependency.

## Stateful accounting, previews, and settlement

`CharterClaimInvariant.t.sol` uses 256 sequences of 64 random handler calls, three
actors, nine eligible IDs, and three ineligible IDs (zero, 1033, and maximum uint256).
The latter still count toward a wallet's NFT balance. Actions mint, transfer, burn,
remint, claim either phase, claim a bounded available batch, transfer all NFTs, and
donate BIC. Raw claim actions also submit duplicates and unauthorized IDs.

After each step, the invariant checks permanent claimants, payment flags, per-wallet
payouts, NFT balances, both preview amounts, fixed supply, and conservation:

`remaining BIC + paid BIC = 800,000,000 BIC + donated BIC`.

Preview expectations use counters maintained from handler actions, not the production
view or a copy of its 1032-ID scan. Each actor starts with a pending entitlement so the
campaign cannot pass solely by failing every claim. Unexpected handler reverts fail
the test. The `afterInvariant` hook removes all remaining NFTs and actually pays every
recorded claimant's unpaid rest; it checks exactly one full share per claimed ID and
leaves all unclaimed allocations and donations in the contract. A deterministic
sequence exercises the handler and this settlement hook as a normal test as well.

The original suites retain coverage of full-range distribution and 200 minor units
of dust, events and aggregate transfers, token failures and callbacks, underfunding,
admin/withdrawal absence, constructors, token supply, and the local launch handoff.

## Limits

The NFT model is installed at the specified CHARTER address and models ERC-721-style
ownership, transfers, balance changes on burn/revocation, and missing-ID reverts.
It deliberately rejects `nextId()` reads. These are offline integration tests;
verification against the deployed Robinhood Chain NFT and the actual factory's
BIC/IMD pool, swarm, and CharterClaim funding transaction remains outstanding.
The local launch model does not prove the real factory's allocation behavior.
