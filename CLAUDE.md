# Finnovest website

Single-file HTML marketing site for Finnovest, deployed via GitHub Pages to finnovest.com.

## Company

Finnovest is a B2B2C fintech platform, HQ Tel Aviv. It is an **advised trading platform**: it
enables licensed advisors at banks, brokerages and wealth management firms to deliver
personalized investment recommendations to thousands of retail investors simultaneously.

Founder & CEO: Tal Brockmann.

## Vocabulary — follow exactly

- **Advised trading** — advisor-issued bundled orders, personalized per client. This is the new
  market category Finnovest is establishing. Use this term consistently.
- **Independent trading** — self-directed single orders.
- Finnovest is a **platform**, never an "engine". Internal component names like
  "compliance engine" are fine; the company is not an engine.
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

## Products

- **Finnovest Core** — institutional, for banks.
- **Finnovest Embedded** — SDK into an existing brokerage app.
- **Finnovest Complete** — full white-label app combining independent trading + advised trading.

Frame the differences around **what the buyer already has**, not installation depth.

## IIA-recognised components

- **Generic Constraints Algorithm** — personalizes recommendations at scale against each client's
  holdings, cash, credit, risk profile and goals.
- **Automatic Order Management Module** — interdependent bundled order execution.

## Clients

FIBI Bank Ltd. · Excellence Trade / Phoenix Investment House · Discount Bank

## Social proof module (reused across the site)

Heading: "Trusted by forward-thinking financial institutions"
Three client logos (white monochrome, transparent background), then a four-stat strip:

- **$19B** assets under advisory  ← $19B is correct. Not $23B.
- **$195M** monthly trading volume
- **53%** registered accounts
- **ZERO** compliance errors

## Design system

- Background: dark navy / deep-teal gradient with a faint starfield texture.
- Headlines: large bold geometric sans, white (Sora; Poppins/Gilroy/Sofia Pro feel).
- Body: Inter, lighter regular weight. Data elements: IBM Plex Mono.
- Accent: mint / spring green ~`#2EE59D` — one emphasis line, plus a solid pill/square CTA
  button with dark text.
- Hero: right-side rounded-corner photo (moody night bokeh, real person on phone) with a
  translucent light-grey notification card overlaid.
- Generous whitespace, left-aligned copy, short punchy microcopy ("Imagine… Now stop imagining").

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
