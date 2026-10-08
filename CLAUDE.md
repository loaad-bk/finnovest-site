# Finnovest website

Single-file HTML marketing site for Finnovest, deployed via GitHub Pages to finnovest.com.

## Company

Finnovest is a B2B2C fintech platform, HQ Tel Aviv. It is the platform for **Advice-driven Trades™**: it
enables licensed advisors at banks, brokerages and wealth management firms to deliver
personalized investment recommendations to thousands of retail investors simultaneously.

Founder & CEO: Tal Brockmann.

## Vocabulary — follow exactly

**Do not change our text. Keep our terminology exactly as written; never replace it with generic wording.**

- **Advice-driven Trades™** — advisor-issued bundled orders, personalized per client. This is the
  new market category Finnovest is establishing. Use this term consistently, with the ™ mark.
  Spelling fixed 16 September 2026: hyphenated, lower-case d. Never "Advice Driven Trades".
  It replaces the earlier term "advised trading" (changed 14 September 2026); do not use
  "advised trading" in new copy.
- **Independent trading** — self-directed single orders.
- **Trade-All™** — the one-tap action that executes a recommendation's entire bundle of orders.
  Spelling fixed 24 September 2026: hyphenated, capital A, with the ™ mark. It replaces
  "Tap-to-Act™" site-wide; do not use "Tap-to-Act" in new copy. The feature is addressed
  with the fixed phrase "One tap to Trade-All™". The stat label
  "Tapped-to-act advice conversion" is still under review; ask before changing it.
- Finnovest is an **operating system** (changed 24 September 2026: "Operating System is what we
  are selling, not a platform"), never an "engine". Internal component names like
  "compliance engine" are fine; the company is not an engine.
- "Live inside your app in weeks" is false. Never claim a deployment time.
- Finnovest holds **no patents**. Its external validation is Israel Innovation Authority (IIA)
  recognition as breakthrough technology, plus IIA funding. Never imply patents.
- In Hebrew the company name is spelled **פינובסט** — single vav, with a ב. Never write
  פינוובסט (double vav). This applies to every Hebrew asset: site, decks, copy.

## The core concept — three-level translation chain

This is the central idea the site must communicate:

1. The head of advisory sets the house trading vision.
2. Each advisor interprets it into a specific recommendation for their book, with written reasoning.
3. Finnovest resolves that single recommendation against every client's individual holdings,
   available cash, credit, risk profile and stated goals — producing thousands of unique
   personalized orders, each executable in a single tap.

Note on funding: the advisor defines a **funding strategy**, not a specific sale. The platform
selects the appropriate holding to sell per client.

## Products (restructured 29 September 2026, from the Altshuler commercial proposal)

**Finnovest Core** is the product: the base system needed to run advised-trading end to end.
Its parts: One-to-Many personalization, Trade-All™ order orchestration, compliance, control and
documentation, and the management and advisor consoles.

**Add-ons**, optional modules on top of Core: Investor onboarding and profiling, Investor app SDK,
Complete white-label app, Long-term savings (planned for 2027, but shown on the site with no
"coming soon" or date label, per the user 29 Sep 2026). The AI
consultation add-on (also 2027) stays off the site for now.

**Implementation**, three ways to deploy, framed around **what the buyer already has**, not
installation depth:

- **Finnovest Connect**: Core integrated into the institution's own systems (banks). Renamed
  from "Finnovest Core" on 29 September 2026 so the word Core belongs to the product only.
  Never use "Finnovest Core" for the bank deployment.
- **Finnovest Embedded**: Core plus the SDK, inside an existing brokerage app.
- **Finnovest Complete**: Core plus a full white-label app combining independent trading and
  advised-trading.

## Navigation (29 September 2026)

Advised-trading · Solutions ▾ (Banks, Brokerages, Wealth managers, For advisors, Advisory
Academy, Case studies) · Product ▾ (Finnovest Core parts, Add-ons, Implementation) · Company ▾
(About, Media, Insights, Events and podcast, Careers, Contact) | For retail investors ▾ (How it
works, Where to get it, Finno Insights, Powered by Finnovest) · Request a demo.
Solutions is organised by institution type. The Solutions, add-on and Case studies pages are
placeholders until written.

## IIA-recognised components

- **Generic Constraints Algorithm** — personalizes recommendations at scale against each client's
  holdings, cash, credit, risk profile and goals.
- **Automatic Order Management Module** — interdependent bundled order execution.

## Clients

FIBI Bank Ltd. · Excellence Trade / Phoenix Investment House · Discount Bank

## Social proof module (reused across the site)

Heading: "Trusted by forward-thinking financial institutions"
Three client logos (white monochrome, transparent background), then a four-stat strip:

- **$20B+** assets analyzed daily  ← $20B+ is correct (user, 7 Oct 2026; was $19B). Not $23B. Label is "analyzed daily", not "under advisory".
- **$200M+** monthly trading volume (user, 7 Oct 2026; was $195M)
- **24%** tapped-to-act advice conversion  ← not "53% registered accounts" (stale, removed 16 September 2026)
- **Zero** compliance errors since 2018

## Design system (adopted 9 September 2026)

A calm editorial system, developed from the look of helloaria.eu. Applied site-wide in
`index.html` in the block headed `NEW DESIGN SYSTEM`. Keep only the logo and the image concepts
from the earlier system; everything else follows this.

- Colour: one solid deep teal `#07282A` for the page hero band and the closing CTA band, white and
  off-white `#F4F8F5` for every section in between. No gradients, no starfield.
- Pastel tiles carry product illustrations and stat figures: mint `#D2F4E3`, lime `#E9F4DC`,
  lilac `#DDD0EA`, teal `#C9E5E2`. Radius 4 to 6px, no borders, no card shadows.
- Mint `#2EE59D` is the single accent: primary pill button, arrow-link hover fill, connector lines.
  On light ground mint text uses `#0B8A5F`.
- Headlines: Instrument Sans, weight 500, very large, tracking -0.02 to -0.025em, line height near
  1.0. One italic phrase per headline is the emphasis device, in the same colour.
- Body: Inter 400. No mono face. Labels and eyebrows are small regular grey text, never uppercase
  or letter-spaced.
- Buttons: pills. Mint with dark text on dark ground, white in the nav, ghost outline secondary.
  Hover is a skewed light wipe sliding through the button.
- Links: dark circle with a chevron followed by the label (class `alink`).
- Motion: halftone dot-matrix canvas graphics in a mint gradient (one-to-many burst in the Home
  hero, tap ripple in every CTA band), a client-logo marquee, scroll reveals, wipes on hover.
- Page types, following the reference site: product-style pages (Home, Products, Platform,
  How it works, Careers, Powered by, Advised trading) open on a dark centred hero with the halftone
  burst, often with a screenshot tile overlapping into the first light section; solution and
  newsroom pages (For advisors, Media, Events, Insights, Where to get it, Academy, Contact) open on
  an off-white left-aligned hero, with a photo or card beside the copy where there is one. Every
  page ends on a dark CTA band except the short retail and directory pages. Bands are classed
  `dk`, `lt` and `lt lt2`. Cards sit on pastel tiles that alternate mint, lime, lilac, teal.
- Hero image concept stays: the real Tap-to-Act hand and phone photo, right of the copy.

Apply this style to any new landing page, hero section, deck or mockup.

## Site structure

Fourteen pages, single self-contained HTML file, all assets and base64 logos inline:
Home · About · What is Advised Trading · Products · Platform · For Advisors ·
Case Studies (Excellence Trade, Discount Bank, FIBI) · Press and Awards · Events and Podcast ·
Advisory Academy (gated) · How It Works (retail) · Where to Get It (retail directory) ·
Finno Insights · Powered By · Careers · Contact

Partner logos are embedded once in CSS as base64 data URIs and referenced by class, to avoid
duplicating the payload.

## Hebrew version

A Hebrew site lives at `/he/` and must be **structurally identical** to the English one.
Both versions need `hreflang` tags pointing at each other. Hebrew pages need `dir="rtl"`.

## Working rules

- Show a mockup or preview before applying changes to the live file.
- Commit before and after any substantial change so it can be reverted cleanly.
- Do not invent metrics. If a figure isn't in this file or already in the site, ask.
