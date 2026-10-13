# Bankers In Control (BIC)

Foundry project for the BIC launch on **Robinhood Chain, chain ID 4663**, paired with IMD. It delivers the fixed-supply `LaunchToken` and one application contract named exactly **`CharterClaim`**. There is no website.

## Build and test

```sh
forge build
forge test
forge fmt --check
```

Solidity **0.8.26** is pinned in `foundry.toml`, with optimization enabled, Paris EVM output, and `bytecode_hash = "none"`. Dependencies and their licenses are vendored as ordinary files under `lib/`; see [DEPENDENCIES.md](DEPENDENCIES.md). No dependency installation, RPC, environment configuration, FFI, or filesystem cheatcode access is needed. The compiler and Foundry are supplied by the execution environment.

Tests cover successful claims, partial/unsorted batches, duplicate and unauthorized attempts, ID limits, NFT transfers and revocations, later mints, unavailable dependencies, insufficient funding, reverting/false/malformed/no-return token transfers, reentrancy, fixed supply, launch allocation, and complete distribution. A stateful invariant test compares randomized mint/transfer/burn/remint/claim/donation sequences against an independent accounting model.

## Launch handoff

Deploy these two production artifacts in order:

| Artifact | Constructor arguments | Purpose |
| --- | --- | --- |
| `src/LaunchToken.sol:LaunchToken` | None | `Bankers In Control` / `BIC`, 18 decimals, exactly 1,000,000,000 BIC minted once to the deploying factory |
| `src/CharterClaim.sol:CharterClaim` | `address token_ = $token` | Permanent claim contract using that deployed BIC token |

Both constructors are nonpayable. CharterClaim has no owner argument, external constructor calls, initializer, configuration setters, or code-existence requirement at construction. It rejects a zero token address; successful deployment alone does not validate the token. Only the delivered LaunchToken is the supported production asset. Do not deploy the models or mocks under `test/`.

**The launch transaction must transfer 800,000,000 BIC to the newly deployed contract registered under the exact name `CharterClaim`.** It must also send 100,000,000 BIC to the BIC/IMD pool and 100,000,000 BIC to the swarm's protocol distributor. The resulting allocation is:

| Destination | Supply fraction | BIC | Minor units |
| --- | --- | --- | --- |
| BIC/IMD pool | 10% | 100,000,000 | `100000000000000000000000000` |
| Swarm | 10% | 100,000,000 | `100000000000000000000000000` |
| `CharterClaim` | 80% | 800,000,000 | `800000000000000000000000000` |

These are the explicit task's allocation terms; they supersede the conflicting generic allocation examples in the supplied background. The token constructor mints the entire supply to the factory, and the application constructor leaves it there. Allocation is the launch system's responsibility in that same transaction; no application function can pull factory funds or perform the launch on its behalf. `test/Deployment.t.sol` models this handoff locally; it does not test the actual network factory.

The separate manifest/deployment step supplies the manifest, factory, distributor, pool addresses, and transactions. No `launch.json`, transaction signer, custom distributor, hook, or replacement factory is included.

Other supplied launch parameters for that step:

| Parameter | Value |
| --- | --- |
| Chain ID | `4663` |
| Paired currency (IMD, 18 decimals) | `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127` |
| Pool fee | `12500` (1.25%) |
| Tick spacing | `60` |
| Manifest initialPrice | `79228162514264337593543950336` |
| Opening market-cap policy | 2,500 IMD for the full supply; deployer derives the effective opening price and currency ordering |

These addresses and chain parameters are supplied assignment inputs, not live-chain observations made by this project. Neither contract calls a pool, router, price oracle, or IMD.

## Claim rules and exact amounts

The immutable NFT reference is `0x69101f92427376FA80476A997d024cf9dC3EaE39`. `MAX_ID` is exactly **1032**. Eligibility uses the fixed range **1 through 1032, inclusive**, never `nextId()` or an enumerable NFT interface.

All calculations use integer BIC minor units:

| Constant | Formula | Minor units |
| --- | --- | --- |
| `ALLOCATION` | 800,000,000 × 10^18 | `800000000000000000000000000` |
| `SHARE` | floor(ALLOCATION / 1032) | `775193798449612403100775` |
| `INSTANT` | floor(SHARE / 10) | `77519379844961240310077` |
| `REST` | SHARE − INSTANT | `697674418604651162790698` |

Each eligible ID follows this sequence:

1. Its **current owner** calls `claim(uint256[] ids)`. Each ID must be in range, exist, belong to the caller, and have no recorded claimant. NFT approvals do not authorize claims. The contract permanently records the caller and pays one INSTANT per ID in a single aggregate BIC transfer.
2. The **same recorded claimant** calls `claimRest(uint256[] ids)` when `CHARTER.balanceOf(msg.sender) == 0`. This checks the entire NFT collection, including IDs above 1032. Each ID must belong to that claimant's recorded claims and have unpaid REST. The contract marks every ID paid and makes one aggregate transfer.

Both functions reject empty arrays and revert the entire batch on any invalid or duplicate ID or failed payout. Arrays can be unsorted, and users may claim subsets in separate transactions. Both functions record effects before paying and use a reentrancy guard. There is no cooldown, deadline, or dependence on timestamps/block numbers.

REST does not query `ownerOf`, so it still works after an NFT has been transferred, burned, or revoked, provided the collection reports a zero balance for the claimant. Transferring or reminting the NFT never changes an existing claimant or resets payment flags. A wallet that receives another Charter before claiming REST must first stop holding all Charters again. Eligibility is a wallet-balance condition at execution, not proof that a person has permanently given up all Charters; the contract cannot prevent reacquisition afterward.

No ID can receive more than SHARE. Unminted/unclaimed IDs keep their allocation locked; an ID in range minted later may still make its first claim. Initial claims lost through a burn before claiming have no recipient unless that ID is subsequently reissued. After every ID completes both stages, **200 minor units** (`0.000000000000000200 BIC`) remain forever. Unclaimed REST, unsolicited deposits, and unclaimed allocations have no expiry or recovery route.

## Views and events

The brief's truncated views line is interpreted as these four interfaces:

| View | Meaning |
| --- | --- |
| `claimant(uint256 id)` | Original claimant, or zero if never claimed |
| `instantClaimed(uint256 id)` | Whether the initial payment succeeded |
| `restClaimed(uint256 id)` | Whether the remaining payment succeeded |
| `claimable(address account) returns (uint256 instant, uint256 rest)` | Current eligible totals, in minor units, across IDs 1–1032 |

`claimable` returns `(0, 0)` for the zero account. It skips reverting `ownerOf` calls for missing/burned IDs when calculating initial eligibility. If the account holds no Charter, it calculates REST exclusively from the recorded claims. A failing `balanceOf` reverts, because eligibility cannot safely be established. The view describes entitlement assuming the full launch funding; it does not cap amounts to an underfunded token balance or reserve a payment.

`claimable` scans at most 1032 IDs and is intended for off-chain `eth_call`. RPC gas limits may need adjustment for this scan. Transaction batches are caller-selected; estimate gas and split them when needed. The all-ID local test proves accounting, not that a batch of 1032 IDs fits the target chain's transaction limits.

Each successful stage emits one event per ID:

```solidity
event Claimed(uint256 indexed id, address indexed account, uint256 amount, bool rest);
```

`rest = false` identifies INSTANT; `rest = true` identifies REST. Events and flags roll back if the aggregate transfer fails. Index these events and use the ID views to construct unpaid batches.

## Operational responsibilities and assumptions

The launch operator must verify the target chain and Founding Charter address/interface, use the actual `$token` produced by this build, configure the requested 10/10/80 split with the exact CharterClaim recipient, and verify the deployed source/constructor argument and funding balances. The deployer supplies the pool key and effective opening price. This assignment builds the contracts; it does not broadcast or verify a live deployment.

After launch, there are **no owner settings or administrative actions**. Claimants submit their own claims and pay transaction gas. No BIC or NFT approvals are needed. Claimants must keep control of the wallet that made the initial claim; no one can change its recorded entitlement if its key is lost.

The fixed Founding Charter must implement reliable ERC-721-style `ownerOf` and `balanceOf`; revoked/burned NFTs must reduce balances for REST eligibility. Its issuer/governance and any changes to that external contract can affect eligibility. Receiving an unwanted Charter can temporarily block REST. CharterClaim cannot transfer or burn NFTs for holders.

Only the plain, non-rebasing, no-fee LaunchToken is supported for launch. SafeERC20 additionally handles no-return tokens and rejects false returns, but does not make fee-charging, rebasing, or dishonest tokens suitable substitutes. The constructor cannot detect a wrong deployment argument, and that immutable argument cannot be repaired.

CharterClaim has **no owner, admin, upgrade, pause, withdrawal, sweep, rescue, arbitrary-call, or token-approval mechanism**. Only the two defined claim payouts can move its BIC. Accidental deposits of any assets cannot be recovered. No administrator can redistribute unclaimed shares or fix an incorrect deployment. The local checks are not an independent security audit; see [the builder review](docs/SECURITY_REVIEW.md) for evidence and remaining integration responsibilities.
