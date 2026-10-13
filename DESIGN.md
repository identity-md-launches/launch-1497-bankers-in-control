# Bankers In Control design system

## Overview

The site helps Founding Charter holders understand and claim BIC on Robinhood Chain. Its visual idea is a printed bank offer with golden handcuffs: warm paper, burgundy ink, a gold cuff illustration, and one prominent claim action. This is an inferred design direction based on the requested playful Bankers takeover, not an existing user-supplied identity.

The production source is `web/src/`. `App.tsx` owns the single-page composition; `style.css` owns tokens and responsive rules; `Artwork.tsx` contains the original SVG illustration and icons. The claim panel is part of the first screen, not a destination below a marketing hero. The explanations and irreversible-burn warning follow the product.

## Colors

The canonical format is hex in `web/src/style.css:3`. Primitive colors feed semantic roles. There is one light theme.

| Semantic token | Value / primitive | Use |
| --- | --- | --- |
| `--color-page` | `--ivory-100`, `#f8f5eb` | Page background |
| `--color-surface` | `--ivory-50`, `#fffcf4` | Claim panel, fields and dialogs |
| `--color-soft` | `--ivory-200`, `#eee8d8` | How-it-works section, neutral notices and hover surfaces |
| `--color-text` | `--wine-900`, `#3d2226` | Primary text |
| `--color-muted` | `#6b6258` | Supporting copy and labels |
| `--color-accent` | `--wine-800`, `#54252c` | Primary action and allocation section |
| `--color-accent-hover` | `--wine-700`, `#6d343c` | Primary-button hover |
| `--color-on-accent` | `--ivory-50`, `#fffcf4` | Text on burgundy |
| `--color-border` | `--ivory-300`, `#d9d0bd` | Panel structure and separators |
| `--color-control` | `#9a8d76` | Input and secondary-button boundaries |
| `--color-gold` | `--gold-300`, `#ecd195` | Decorative coin and allocation emphasis |
| `--color-gold-text` | `--gold-700`, `#705019` | Dark gold labels and lock icons |
| `--color-focus` | `#245c83` | 3px keyboard focus outline with 4px offset |
| `--color-success` / `--color-success-bg` | `#315a3e` / `#edf2e6` | Eligible/confirmed text and confirmed-payout notice |
| `--color-error` | `#a12b29` | Recoverable error text and invalid field border |

The allocation chart additionally uses `#b99b91` for the swarm segment and `#906971` for dividers on burgundy. It is labeled with text and percentages. These are local illustration/data colors, not additional action styles. The cuffs use their own gold gradients and linework within the SVG; no text is laid over the illustration.

Rendered measurements from the final design probe: muted step copy on the soft section is **4.89:1**, and the gold coin's dark “B” on gold is **4.95:1**. All text pairs measured by the probe passed its 4.5:1 / 3:1 thresholds. This is not a claim that every possible browser/composite background was measured. Full evidence is in `docs/WEBSITE_VALIDATION.md`.

## Typography

Fonts are local WOFF2 assets in `web/public/fonts/`, with the original SIL Open Font License texts beside them. They are preloaded in `web/index.html`; CSS uses `font-display: swap`.

- Body/interface: **DM Sans**, then Arial, sans-serif. The file supports variable weights; the implementation uses 400, 600 and 700.
- Display: **Fraunces**, then Georgia, serif. Headings and large amounts use 600. No italic face or synthetic style is required.
- The root sets `font-synthesis: none`, 16px, 1.55 line height and font smoothing. Inputs remain at the base 16px size. Long explanatory copy is bounded by its columns or a 60–65ch measure.

| Token | Desktop | At ≤848px | At ≤688px | Role |
| --- | --- | --- | --- | --- |
| `--text-sm` | 14px | 14px | 14px | Hints, status, navigation and contract addresses |
| `--text-base` | 16px | 16px | 16px | Body, inputs and buttons |
| `--text-lead` | 20px | 20px | 20px | Step headings; desktop lead copy |
| `--text-title` | 28px | 28px | 28px | Claim heading, small section title, percentages |
| `--text-section` | 44px | 36px | 36px | Section headings and per-Charter amount |
| `--text-display` | 76px (56px at ≤1088px) | 56px | 44px | Main headline |

Each width uses at most six sizes and three weights. H1 line height is 1.04 (1.05 on mobile), with −0.055em tracking (−0.045em mobile). Section headings use 1.12 / −0.04em, H3 uses 1.3 / −0.015em, and smaller claim headings use −0.03em. Large numeric text uses tabular numerals. Headings balance wrapping and allow long words to wrap under text enlargement. Addresses remain fully selectable and wrap anywhere; shortened wallet labels have a full-address dialog. Displayed BIC amounts truncate to two decimal places, with exact values available in the transaction review.

## Layout

`.wrap` is the shared content primitive: maximum 76rem / 1216px including gutters. Desktop gutters use `--space-8: 2rem`. They reduce to 1.25rem at ≤43rem and 1rem at ≤23rem. Spacing uses a repeated 4/8/12/16/24/32/48/64px rhythm; large sections use 80–96px desktop and 48px mobile. Component-specific icon/button gaps include smaller optical adjustments.

- Desktop hero: two columns, explanation and illustration on the left, claim panel on the right. The panel is not sticky; expanded eligibility and transaction states grow in normal document flow.
- At **68rem / 1088px**, reduce the headline, gaps and panel padding.
- At **53rem / 848px**, tighten the two-column hero; hide one navigation item while retaining the other two.
- At **43rem / 688px**, use a single column and hide the decorative hero illustration. Keep the product name, headline, brief description and claim action above the mobile fold. Navigation links disappear; all sections remain in document order with return-to-claim links. Steps become a vertical sequence, allocation and FAQs stack, and dialog actions stack.
- At **23rem / 368px**, tighten gutters and panel padding and simplify small controls.
- The claim panel is an inline-size container. Below **15rem of available panel width**, its split and wallet controls stack and decorative button icons disappear. This also handles 200% text enlargement.

Rows and buttons wrap rather than clip. The header can grow if labels become larger. The allocation grid uses `minmax(0, 1fr)`, its data rows wrap, and contract actions wrap. No horizontal overflow was detected at 320, 390, 768 or 1440px. A 390px viewport with the root font doubled to 32px also reflowed. Browser-native zoom, RTL and translated content were not verified.

## Elevation & Depth

The design is flat: no panel shadows, gradients behind text or nested decorative cards. Thin borders structure the claim panel, input fields, FAQ rows and contract ledger. Tonal sections separate the story. Native dialogs use a `rgb(40 22 20 / .48)` backdrop and the browser's top layer; the background becomes inert while open. The only gradients are inside the decorative SVG.

## Shapes

`--radius-small: .375rem` (6px) belongs to buttons, fields and notices. `--radius-panel: .875rem` (14px) belongs to the claim panel and dialogs. Coin/seal marks are circular. Controls have borders when they are secondary or editable, with 48px primary-button minimum height and 44px minimum for most supporting actions. The mobile brand link is 34px high, comfortably separated from its neighbor and above the 24px baseline.

## Components

| Component/pattern | Source | Behavior |
| --- | --- | --- |
| `ClaimPanel` | `web/src/App.tsx:33` | Disconnected call to action, optional public lookup, connected stage switch, labeled ID input, result, review, pending/confirmed/error states. Controls that could create a duplicate pending transaction are disabled. |
| `Modal` | `web/src/App.tsx:12` | Native `<dialog>`, accessible heading, close button and Escape handling, scroll containment, focus return. Used for wallet selection and transaction review. |
| Buttons | `web/src/style.css:69` | `.primary` uses burgundy; `.secondary` is bordered; `.text-button` is underlined or in an established action zone. Every action is a native button or link. |
| Field and stage switch | `web/src/style.css:155` | Visible label, numeric keyboard, adjacent hint/error; selected stage uses both `aria-pressed` and an underline. Each stage button is independently keyboard operable. |
| Eligibility and notices | `web/src/style.css:167` | Text explains ready, locked, already paid, wrong owner, unavailable RPC and recoverable failure. Success includes a receipt link and the recipient. Color supplements explicit wording. |
| `ExternalLink` | `web/src/App.tsx:29` | External explorer link, arrow and accessible new-tab suffix. Contract addresses remain visible nearby. |
| FAQ | `web/src/App.tsx:172` | Native `<details>/<summary>` with plus/minus affordance; multiple answers may stay open. |
| Artwork/icons | `web/src/Artwork.tsx` | Original code-native gold cuffs. Decorative SVGs are hidden from assistive technology; icons inherit text color and do not carry status alone. |

Only supported interaction transitions run: 120ms background-color/transform on buttons and 0.96 press scale under `prefers-reduced-motion: no-preference`. Hover styles are pointer-capability guarded. Reduced motion removes these effects and smooth scrolling. There is no autoplay, looping animation, theme switch or carousel.

## Do's and Don'ts

- Start another section inside `.wrap`, reuse the six-size scale and use the semantic color tokens.
- Keep one prominent filled action in a task context; use secondary buttons and links for alternatives.
- Keep the takeover voice in explanations. Describe wallet fees, burns and errors plainly.
- Keep the claim panel above decorative material at narrow widths. Never fix wrapping by hiding financial values or clipping controls.
- Keep the source SVG and local fonts when exporting. Do not introduce externally fetched runtime art or a second icon family.
- Reuse the contract configuration and verified ABIs for new claim UI; do not duplicate addresses in components.
- For another page, reuse the header, `.wrap`, button patterns and typography, then add a hash section or explicitly exported static page. The site has no server-side route rewriting.

Guidance attribution: Jakub Krehel's Better Interface (MIT, commit `267330e1adfc66a718fb65fa6918c1f06d0a689e`) and Paul Bakaus's Impeccable documentation method (Apache-2.0, commit `9d715cc4f5564a990ca8345abfdd5df6dc9b41c8`). The supplied license texts are preserved in `docs/DESIGN_GUIDANCE_LICENSES.txt`.
