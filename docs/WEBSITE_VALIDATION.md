# Website validation and design review

Completed by the implementation worker on **2026-10-13**. This is a record of local observations, not independent certification.

## Scope and assumptions

**Complete for the stated website scope**, with the browser/device and live-signing limitations below. The delivered source is `web/`; the publisher-ready export is `dist/`. Existing Solidity contracts, Foundry settings and vendored dependencies were preserved. Nothing was deployed, re-minted, signed or broadcast on chain.

The site is one English page with hash navigation. The main flow is connect an injected wallet, select the 10% claim or 90% release, check one Charter ID, review, then confirm in the wallet. Public ID lookup, token-address copying, contract links and FAQ disclosures also work. No collection-wide scan, NFT transfer/burn, trading UI, price feed, wallet-key custody or backend is implied. Manual ID entry and one ID per transaction keep RPC work bounded.

The visual direction is an original printed bank offer: ivory paper, burgundy typography and a gold handcuff drawing. The requested playful takeover voice is retained around plain claim rules. The principal warning states that an eligible Charter's first claim must happen before burning/releasing it. The final 90% requires the original claimant wallet's **entire** Charter balance to be zero, including IDs above 1,032; burning is one possible path, not a contract requirement.

## Acceptance coverage

| Requirement | Result and evidence |
| --- | --- |
| Usable responsive website with working primary interactions | Implemented. Chromium exercised both claim stages and recovery states using explicit wallet/RPC fixtures. Real read-only RPC checks also passed. |
| Source, lockfile and production export with relative assets | `web/package.json`, `web/package-lock.json`, React/TypeScript source, and complete `dist/`. Vite `base: './'`; production served under `/preview/`. [Export manifest](validation/export-manifest.json) lists every file's bytes and SHA-256. |
| Production build, typecheck and useful interaction checks | Locked installation, no-emit TypeScript, Vite build and **24/24 browser checks** passed in the final isolated run. [Results](validation/interaction-results.json). |
| Pinned Better Interface applied and reviewed in six domains | Applied during implementation. Coverage and corrected findings are below. Attribution and both supplied licenses are retained in [DESIGN_GUIDANCE_LICENSES.txt](DESIGN_GUIDANCE_LICENSES.txt). |
| Product/action on the first screen at 390px | Observed at 390×844. The main connect button is 300×48px, approximately y=531–579; product name, headline and claim panel are visible. [Screenshot](validation/mobile-first-screen.png). |
| Title, favicon, description, og:title, og:image | Present in exported `index.html`; local SVG favicon and 1200×630 PNG share card included. Final host is not yet assigned, so the share-image URL is relative. |
| Root DESIGN.md reflects final source | [DESIGN.md](../DESIGN.md) records actual tokens, type roles, components, motion and breakpoints. |
| README explains installation, preview and rebuild | [README.md](../README.md) documents isolated npm installation/build, static preview, rechecks, runtime requirements and limitations. |

## Commands actually run

From the repository root (temporary dependencies and browser packages were kept under `/tmp`):

```sh
forge build --out /tmp/bic-contracts-out --cache-path /tmp/bic-contracts-cache

PLAYWRIGHT_BROWSERS_PATH=/tmp/sentra-browsers \
XDG_CONFIG_HOME=/tmp/bic-browser-config \
XDG_CACHE_HOME=/tmp/bic-browser-cache \
node web/scripts/build.mjs \
  --verify-contracts /tmp/bic-contracts-out \
  --test --live --out /tmp/bic-release-validation

PLAYWRIGHT_BROWSERS_PATH=/tmp/sentra-browsers \
IMD_PLAYWRIGHT=/tmp/bic-work/web/node_modules/playwright/index.mjs \
XDG_CONFIG_HOME=/tmp/bic-browser-config \
XDG_CACHE_HOME=/tmp/bic-browser-cache \
node .imd/reads/skills/design-critic/scripts/taste.mjs --out test/scratch/taste

git diff --check
```

- **Foundry build: exit 0.** Solidity 0.8.26; 40 files compiled. Existing linter warnings about calls/reverts inside bounded claim loops and strict zero-balance comparisons were reported. Contract source was not edited, so the contract test suite was not rerun for this frontend-only change.
- **Final build helper: exit 0.** `npm ci` installed 90 packages into a fresh temporary project. `tsc --noEmit` passed, then Vite 7.1.12 compiled 429 modules. The production export has 10 files and **690,941 bytes** including all local fonts, licenses and imagery. The main JavaScript bundle is 497.38 kB / 153.32 kB gzip; CSS is 21.85 kB / 4.93 kB gzip.
- **Final browser validation: 24/24 passed, exit 0.** It served the built export under a gateway-like `/preview/` subpath, then closed its server and browser. The helper copied these same built bytes into repository `dist/` after successful checks. The temporary export path recorded in the JSON is therefore expected to have been removed.
- **Final taste@1: 16/16 passed, exit 0.** Its retained measurements are in [taste.json](validation/taste.json). The pinned probe itself is an input removed by the assignment and is not bundled into the site.
- **Whitespace/path checks:** `git diff --check` passed. Existing protected configuration/dependency paths and ignore files were unchanged. No repository `node_modules`, caches, dependency archives or submodules were introduced. Source plus export plus evidence are comfortably below 8 MiB; see the final size record in `validation/submission-size.json`.

## Contract evidence

The initial [verification snapshot](validation/contract-verification.json) and the final build's independent recheck agree:

| Contract | Canonical ABI Keccak-256 | Live runtime match |
| --- | --- | --- |
| LaunchToken | `38880b8e56d42ce900f744a7908c7139632a49f1c3f33385c64ceaed29d37bee` | Exact compiled-runtime match |
| CharterClaim | `ff707ed90df8d3146dca908da91f5b9b234b5fee20aa0ad6ad222682091c6ff2` | Exact match after filling compiler-reported immutable token slots |

Source commit: `8221822a3749195df6b6b355a832d147ec98e3bf`. Addresses and chain parameters came from the pinned deployment/network inputs. Charter address and constants were confirmed through the live getters; the external NFT has deployed code. The first check found `800000000000000000000000066` BIC minor units in CharterClaim. This is an observation at that time, not a permanent balance: later live checks saw claims reduce the reserve.

The browser rereads the reserve and verification on demand. Before submission, `web/src/chain.ts:115` checks wallet identity, deployment, eligibility, funding and an `eth_call` simulation. It submits only to the pinned CharterClaim with `claim([id])` or `claimRest([id])`. `web/src/chain.ts:140` checks the expected event's ID, account, amount and stage before the UI says a claim succeeded.

The live browser smoke check read Charter #1 without connecting. Its actual observed response and reserve are in `interaction-results.json` under `liveObservation`; [live screenshot](validation/live-read.png). It sent no wallet transaction. All wallet/transaction success screenshots are explicitly **synthetic test fixtures**, not live payouts.

## Better Interface: six-domain coverage

| Domain | Coverage | Evidence and limits |
| --- | --- | --- |
| Accessibility | **Checked** | Native buttons, links, labeled input, details/summary and dialog. Keyboard opens the connect dialog, traverses its controls, Escape closes, and focus returns to the trigger. Input errors use `aria-invalid`/description and focus. Stable status regions accompany pending/results. Axe returned zero WCAG A/AA violations in initial, invalid-input, wallet-dialog, eligible-claim and review-dialog states. [Focus screenshot](validation/keyboard-focus.png). Screen-reader sessions, forced-colors rendering and physical assistive devices were not verified. |
| Layout | **Checked** | 320×812, 390×844, 768×1024 and 1440×1000 in interaction validation, plus the probe's 320/390/1440 measurements. No horizontal scrolling; probe found no text overlap, clipped text or controls covering content. 390px first-screen action was inspected. Root text doubled to 32px reflowed at 390px. Browser-native zoom, localization and RTL mirroring were not verified. |
| Writing | **Checked** | Product sentence, verb-first actions, wallet/no-wallet guidance, ID-bound errors, initial/rest rules, already-paid/wrong-owner/locked states, and claim-before-burn wording read against Solidity. Removed repeated slogan patterns. Final probe counted 16 prose words on the first mobile screen (limit 60). The requested humor remains in low-stakes explanations; fee and irreversible-action copy is plain. |
| Typography | **Checked** | Both intended local fonts loaded in Chromium. Six sizes per measured width, two font families and three weights. Numbers use tabular numerals; full addresses wrap; modal exact amounts remain accessible. Inspected mobile/desktop screenshots and the enlarged-text case. No synthetic italic is used. Native Safari font rendering was not verified. |
| Colors | **Checked** | Semantic tokens reviewed against rendered surfaces. Final probe found all measured text pairs above 4.5:1 (3:1 large). The lowest measured normal-copy ratio was 4.89:1; the repaired coin letter is 4.95:1; primary connect text is 12.21:1. Errors and success include text, not color alone. Decorative SVG gradient contrast is not claimed as measured text contrast; there is no dark theme to test. |
| UI details | **Checked** | Border-only flat panels; consistent original SVG icons; native disclosure indicators; initial, checking, empty/unavailable-wallet, invalid ID, locked/eligible, wrong-chain, review, pending, confirmed and failed states. Fixture tests exercised both payout selectors, rejection/retry and incorrect receipts. Reduced-motion emulation confirmed zero button-transition duration. Hover/press rules and forced-colors fallbacks were source-reviewed; every hover combination and animation-panel slow playback were not separately inspected. |

Not applicable to this implementation: alternate themes, media autoplay, carousels, drag-and-drop, multiple locales and live market comparisons. Their absence was not scored as a pass.

## Findings, fixes and rechecks

| Severity / source | Finding and user impact | Fix and evidence |
| --- | --- | --- |
| **High**, `web/src/style.css:6`, `.coin-mark` | First probe measured the small gold “B” at 4.33:1, below the normal-text threshold on the primary surface. | Changed `--gold-700` from `#79591f` to `#705019`. Final rendered ratio 4.95:1; probe contrast check passed. |
| **High**, `web/src/App.tsx:223`, `:232`, `:243`, `:249` | Eight short two-part slogan lines repeated throughout the page and distracted from the actual contract explanation. | Kept the main headline and claim-before-burn instruction. Rewrote secondary headings/descriptions in ordinary sentences. Final probe counts two such lines and passes. |
| **Medium**, `web/src/App.tsx:243` | Axe flagged `aria-label` on a generic allocation-bar div (`aria-prohibited-attr`). | Assigned `role="img"` to the labeled chart. The allocation remains available as adjacent text/percentages. All five final Axe audits pass. |
| **High**, `web/src/style.css:28`, `:40`, `:61`, `:115`, `:143`, `:318` | At 200% root text size, the header, unbroken amount, allocation rows, long heading and contract actions could exceed the viewport. | Allowed meaningful wrapping, `minmax(0,1fr)` grid tracks and the narrow claim-panel container adaptation. The final 390px/32px-root test reports no horizontal overflow and can open the wallet guidance dialog. Normal-width layouts were rechecked. |
| **High**, `web/src/chain.ts:140`, `web/src/App.tsx:96` | Source review found that a successful receipt with any log from CharterClaim could be attributed to the requested claim, even if a replacement had claimed a different ID. | Decode and match the full expected event. A successful fixture receipt for ID 43 while ID 42 was requested now produces “Claim not completed”; reverted receipts also never show success. |
| **Medium**, `web/src/wallet.ts:28` | Source review identified that an older asynchronous identity refresh could finish after a newer wallet event/disconnect. | Added identity request sequencing and invalidation on listener cleanup/disconnect. Final account-change test discards a previously eligible result; pre-submission identity checks remain in place. The exact late-response ordering was source-reviewed rather than separately timed in a browser. |

No known unresolved implementation finding blocks the stated claim flow. The remaining limits below are explicit; they do not turn simulated transactions into live evidence.

## Retained visual evidence

- [390px first screen](validation/mobile-first-screen.png): product and main action visible.
- [1440px first screen](validation/desktop-first-screen.png) and [complete desktop page](validation/desktop-full.png): hierarchy, original cuffs illustration and all sections.
- [Transaction review](validation/claim-review.png), [pending](validation/claim-pending.png), [confirmed](validation/claim-success.png): synthetic wallet/RPC fixtures.
- [Locked remainder](validation/rest-locked.png) and [RPC unavailable](validation/rpc-unavailable.png): recoverable guidance, not fake balances.
- [Keyboard focus](validation/keyboard-focus.png) and [live read](validation/live-read.png).

The full interaction run also produced wallet guidance, wrong-network and enlarged-text images under `/tmp/bic-release-validation`; those are not required runtime assets and were not all copied into the submission. The retained result JSON lists their original names. Screenshots document the tested state, not every possible wallet extension.

## Limitations and unperformed checks

1. The assigned MCP browser tool returned: `Browser "chrome-for-testing" is not installed; expected executable at /home/seat/.cache/ms-playwright/chromium-1246/chrome-linux64/chrome`. It could not supply a managed preview. A bounded foreground Playwright script instead served and inspected the actual export under `/preview/` and shut down afterward.
2. WebKit was downloaded under `/tmp`. Its initial launch reported missing host libraries; a local library-extraction workaround then failed to produce a completed browser session and was interrupted. **No WebKit/Safari pass is claimed.** Chromium rendering and useful interaction checks completed independently. Physical iPhone/device behavior is unverified.
3. No real browser wallet extension, hardware wallet, WalletConnect session or signed mainnet claim was tested. Both calldata paths and wallet behaviors were checked with explicitly synthetic EIP-1193 providers, then live chain reads independently verified the configured contracts. EIP-6963 discovery is implemented and source-reviewed; the fixture suite exercised the injected fallback.
4. Receipt timeout/retry and replacement tracking are implemented; the suite checked pending, confirmed, reverted and unexpected-event receipts. It did not wait out the full 120-second timeout or execute every wallet replacement/cancellation sequence. Pending state is not persisted across reloads; the README and explorer links explain recovery.
5. Native browser zoom, screen readers, all forced-colors combinations and translated/RTL variants were not tested. The 200% check enlarges root text; it is not browser-native zoom. Automated Axe results are not a full accessibility compliance claim.
6. RPC availability, public-chain changes and wallet support are external dependencies. The app reports failure and disables claims if its verification cannot complete. Displayed reserves are snapshots with a block number and refresh action.
7. The share image is locally bundled and its relative URL resolves under the tested subpath. Social crawlers requiring an absolute `og:image` URL may need the final publisher URL after hosting is assigned. Hosting itself is outside this task.
