# Bankers In Control (BIC)

BIC is live on **Robinhood Chain, chain ID 4663**, paired with IMD. This repository contains the original Foundry contracts and a responsive claim website in `web/`, with its complete static production export in `dist/`.

The Bankers are taking over. The website explains the golden handcuffs: claim 10% with an eligible Founding Charter, then release the remaining 90% from the same wallet after its total Charter balance reaches zero. It does not burn or transfer NFTs.

## Website: install, build and preview

Requires Node.js **22.12+** (validated with 24.9.0), npm and network access for initial dependency installation. From the repository root:

```sh
node web/scripts/build.mjs
python3 -m http.server 4173 --bind 127.0.0.1 --directory dist
```

Open `http://127.0.0.1:4173/`. Stop the preview with Ctrl+C. The build helper copies `web/` to a temporary directory, runs **`npm ci`**, **`npm run typecheck`** and **`npm run build`**, replaces `dist/` only after success, then deletes the temporary project. It leaves no `node_modules` or cache inside the repository. `web/package.json` and `web/package-lock.json` are the complete frontend manifest and lockfile. Existing Foundry configuration and dependencies are unchanged.

To rebuild after editing `web/src/` or `web/public/`, run the same build command. The underlying standard Vite project also provides `dev`, `typecheck`, `build`, `preview` and `test` npm scripts when installed in a separate working directory.

### Browser validation

Install Playwright's browser outside the repository, then use the isolated build-and-test helper:

```sh
npm install --prefix /tmp/bic-browser-tools --cache /tmp/bic-npm-cache playwright@1.61.1
PLAYWRIGHT_BROWSERS_PATH=/tmp/bic-browsers /tmp/bic-browser-tools/node_modules/.bin/playwright install chromium
PLAYWRIGHT_BROWSERS_PATH=/tmp/bic-browsers node web/scripts/build.mjs --test --out /tmp/bic-validation
```

On a sandbox that cannot write browser configuration under the home directory, also set `XDG_CONFIG_HOME=/tmp/bic-browser-config` and `XDG_CACHE_HOME=/tmp/bic-browser-cache`. Linux browser system libraries must be present. `--live` adds a **read-only** check against the pinned public RPC; default interaction checks use explicitly synthetic wallet/RPC fixtures. `--webkit` attempts an additional WebKit check and records an unavailable runtime as a limitation. Results and screenshots go to the chosen `/tmp` folder, never into application code.

### Static delivery

`dist/index.html` and all required scripts, styles, fonts, favicon and share image are included. Vite uses `base: './'`; links within the app are hash anchors. The export was served and tested under `/preview/`, including local asset loads. The publisher must serve the committed `dist/` as-is; it does not need npm, a backend or a build step. No publishing command or on-chain deployment was run.

The share image uses `./social-card.png`, because the final host is assigned after this job. The image is bundled and works at a static subpath. Social platforms that require an absolute `og:image` URL may need the publisher to set that URL once the final host is known.

## Website integration

- **LaunchToken:** `0x642c34606276849de4ae27b190abd9dff47c9aa9`
- **CharterClaim:** `0x186aafebd0053324a1ae15fbe04daf437b544faf`
- **Founding Charter:** `0x69101f92427376FA80476A997d024cf9dC3EaE39`, confirmed from the live `CHARTER()` getter and pinned source.
- **RPC order:** `https://robinhood-rpc.publicnode.com`, then `https://rpc.mainnet.chain.robinhood.com`.

`web/src/contracts/deployment.json` and `network.json` preserve the relevant pinned deployment/network values. ABIs were compiled from source commit `8221822a3749195df6b6b355a832d147ec98e3bf`. Canonical JSON sorts object keys recursively, preserves array order and is hashed with Keccak-256. Both ABI hashes match their supplied attestations. Both live runtimes exactly match the compiled artifacts after inserting CharterClaim's verified immutable token address. See [contract verification](docs/validation/contract-verification.json).

To independently repeat those checks without changing Foundry configuration:

```sh
forge build --out /tmp/bic-contracts-out --cache-path /tmp/bic-contracts-cache
node web/scripts/build.mjs --verify-contracts /tmp/bic-contracts-out
```

At runtime, the page verifies the RPC chain ID, both runtime code hashes, CharterClaim's token/Charter getters and Charter code presence. It reads the live claim-contract BIC balance. Before requesting a transaction it repeats verification and eligibility, checks available funding, simulates the exact `claim([id])` or `claimRest([id])` call and rechecks the wallet identity. Success requires a successful receipt containing the expected `Claimed` event for the selected ID, recipient, stage and amount.

Wallet support uses EIP-6963 provider discovery with an injected `window.ethereum` fallback. The page requests accounts only after a visitor chooses a wallet. Wrong-chain wallets can switch/add the pinned chain. No WalletConnect project ID, private key, backend or analytics is used. Visitors without an injected provider receive wallet-browser guidance. The interface deliberately handles **one ID per transaction** and asks for the ID from the holder's NFT; it does not scan the collection or auto-discover every holding. It does not request token/NFT approvals.

A pending claim is monitored in the current page, with an explorer link and a confirmation retry after timeout. Pending state is not persisted across reloads; check the wallet/explorer before sending again. Eligibility is always reread, and the contract prevents duplicate payouts. No NFT burn workflow is exposed because the pinned Charter interface supplies ownership/balance reads, not an attested burn method.

## Website validation results

Actual worker checks on 2026-10-13:

- Locked dependency installation, TypeScript no-emit check and production build passed.
- **24/24 Chromium checks passed** against the export: responsive/subpath rendering, local fonts, wallet/keyboard flows, form bounds, FAQ, clipboard, reduced motion, both claim stages, network switching, rejection/retry, stale eligibility, insufficient reserve, pending/success/reverted/unexpected receipts, RPC failure recovery and live read-only lookup.
- Axe WCAG A/AA checks found **zero violations in five states**. Text enlarged to 200% reflowed at 390px. The first 390px screen displays the product and the claim action.
- The pinned **taste@1 probe passed 16/16 checks** at its 320, 390 and 1440px measurements; full interaction validation also covered 768px.
- The supplied MCP browser launcher could not start because its expected Chrome binary was missing. Local Playwright Chromium was used successfully. WebKit was attempted, but its system-library/startup problems prevented a completed check. Real wallet extensions, signed/broadcast claims, physical iPhones, screen readers and browser-native zoom were **not** tested.

[DESIGN.md](DESIGN.md) describes the final implementation. [Website validation](docs/WEBSITE_VALIDATION.md) records six-domain coverage, findings, fixes, commands, screenshots and limitations. These are worker observations, not independent certification.

## Original contract project

### Contract build and test

```sh
forge build
forge test
forge fmt --check
```

Solidity **0.8.26** is pinned in `foundry.toml`, with optimization enabled, Paris EVM output, and `bytecode_hash = "none"`. Dependencies and their licenses are vendored as ordinary files under `lib/`; see [DEPENDENCIES.md](DEPENDENCIES.md). No dependency installation, RPC, environment configuration, FFI, or filesystem cheatcode access is needed. The compiler and Foundry are supplied by the execution environment.

Tests cover successful claims, partial/unsorted batches, duplicate and unauthorized attempts, ID limits, NFT transfers and revocations, later mints, unavailable dependencies, insufficient funding, reverting/false/malformed/no-return token transfers, reentrancy, fixed supply, launch allocation, and complete distribution. A stateful invariant test compares randomized mint/transfer/burn/remint/claim/donation sequences against an independent accounting model.

## Original launch handoff (historical)

The completed launch deployed these two production artifacts in order. They are live; do not redeploy them as part of website work:

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

The separate manifest/deployment step supplies the manifest, factory, distributor, pool addresses, and transactions. The later launch process supplied `launch.json` and the deployment. No transaction signer, custom distributor, hook, or replacement factory is included in this website.

Other supplied launch parameters for that step:

| Parameter | Value |
| --- | --- |
| Chain ID | `4663` |
| Paired currency (IMD, 18 decimals) | `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127` |
| Pool fee | `12500` (1.25%) |
| Tick spacing | `60` |
| Manifest initialPrice | `79228162514264337593543950336` |
| Opening market-cap policy | 2,500 IMD for the full supply; deployer derives the effective opening price and currency ordering |

These pool addresses and chain parameters are pinned launch inputs; the website does not query pool state. Neither contract calls a pool, router, price oracle, or IMD.

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

The launch operator must verify the target chain and Founding Charter address/interface, use the actual `$token` produced by this build, configure the requested 10/10/80 split with the exact CharterClaim recipient, and verify the deployed source/constructor argument and funding balances. The deployer supplies the pool key and effective opening price. Those responsibilities describe the original contract-build handoff. The website follow-up verified the live token and claim runtimes read-only, as documented above; it did not broadcast transactions.

After launch, there are **no owner settings or administrative actions**. Claimants submit their own claims and pay transaction gas. No BIC or NFT approvals are needed. Claimants must keep control of the wallet that made the initial claim; no one can change its recorded entitlement if its key is lost.

The fixed Founding Charter must implement reliable ERC-721-style `ownerOf` and `balanceOf`; revoked/burned NFTs must reduce balances for REST eligibility. Its issuer/governance and any changes to that external contract can affect eligibility. Receiving an unwanted Charter can temporarily block REST. CharterClaim cannot transfer or burn NFTs for holders.

Only the plain, non-rebasing, no-fee LaunchToken is supported for launch. SafeERC20 additionally handles no-return tokens and rejects false returns, but does not make fee-charging, rebasing, or dishonest tokens suitable substitutes. The constructor cannot detect a wrong deployment argument, and that immutable argument cannot be repaired.

CharterClaim has **no owner, admin, upgrade, pause, withdrawal, sweep, rescue, arbitrary-call, or token-approval mechanism**. Only the two defined claim payouts can move its BIC. Accidental deposits of any assets cannot be recovered. No administrator can redistribute unclaimed shares or fix an incorrect deployment. The local checks are not an independent security audit; see [the builder review](docs/SECURITY_REVIEW.md) for evidence and remaining integration responsibilities.
