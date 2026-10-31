# hsbg.cards API notes (research only, nothing implemented)

Read on 2026-11-01. Pages: https://hsbg.cards/api-docs, https://hsbg.cards/terms (last updated 2 Mar 2026), https://hsbg.cards/privacy (29 Oct 2026), https://hsbg.cards/about, https://hsbg.cards/llms.txt, spec at https://hsbg.cards/api/v1/openapi.json (OpenAPI 3, v1.0.0, license field just says "See terms"). Live checks: a handful of GETs with curl, no key.

## 1. What exists

Base URL `https://hsbg.cards/api/v1/`. Card data and card renders only. **No tribe icon endpoint and no tavern-tier badge endpoint are documented** (the OpenAPI path list: healthz, cards, cards/suggest, cards/batch, cards/{id}, .../field/{f}, .../related, .../image, .../skins, skins/{id}). `/api/v1/tribes` is not a real route (returns the site 404 page); `/tribes/beast.png` is 404 too.

Useful endpoints (all GET works without a key; only `/cards/suggest` needs a key):
- `GET /cards?cardType=minion&tribe=beast&tier=3&limit=200&offset=0&fields=id,name,tier,minionTypes` returns `{"data":[...],"pagination":{"total":83,"limit":1,"offset":0,"nextOffset":1},"filters":{...}}`. Max limit 200, so the full minion list is a few paged calls.
- `GET /cards/{id|slug|name}` returns `{"data":{"id":64038,"slug":"sellemental","name":"Sellemental","image":"/cards/production/thumbs/full/minions/elemental/64038-sellemental.webp","imageGold":"..._golden.webp","attack":3,"health":3,"tier":2,"cardType":"minion","minionType":"Elemental","minionTypes":["Elemental"],"keywords":[],"externalId":"BGS_115","dbfIdGold":64041,"pool":true,...}}`. `externalId` is the Hearthstone card id (e.g. `BGS_115`), which is what Power.log gives us, so lookup by `externalId` may work (not tested; numeric dbf id and slug were the documented identifiers).
- `GET /cards?identifiers=a,b,c` (about 20) or `POST /cards/batch` (up to 100); a batch counts as 1 request.
- `GET /cards/{id}/image` answers `302` to a static file, e.g. `/cards/production/thumbs/full/minions/elemental/64038-sellemental.webp`. Docs say one size only: 512 px wide WebP, about 57 KB. `?golden=true` gives golden art.
- Tier badges exist only as **site assets, not API**: `https://hsbg.cards/tiers/Tier1.png` ... `Tier7.png` (Tier1.png is 7.6 KB, `image/png`, ETag, `cache-control: public, max-age=86400`). Found in the homepage HTML; undocumented and could move. They are Blizzard artwork.
- Tribe icons: none found in the homepage HTML or the tribe page. Tribe values come as English names in `minionTypes`: Aberration, Beast, Demon, Dragon, Elemental, Mech, Murloc, Naga, Pirate, Quilboar, Undead, All (per llms.txt filter list).

Headers: JSON has `cache-control: public, max-age=3600, s-maxage=86400, stale-while-revalidate=86400`, `x-api-version: 1.0.0`, `x-ratelimit-limit/remaining/reset`. The JSON responses I saw had no ETag (not verified on every endpoint). Static files (tiers PNG) have ETag and Last-Modified. The 302 image redirect has `max-age=86400, immutable`. Docs say v1 is frozen and breaking changes would ship as v2.

## 2. Terms (paraphrased)

- Ownership: card art, names and assets belong to Blizzard; the site's own code, design and curated data belong to the site team. The site is part of the Hearthstone Creator Program but is not affiliated with Blizzard. The About page says Blizzard's policies allow non-commercial fan projects.
- Allowed: downloaded card images and data may be used "for personal use, content creation, guides, videos, streams, and community projects". Nothing in the Terms bans an app from calling the API at runtime.
- Attribution: they "kindly ask" for credit to HS BG Cards with a link to hsbg.cards; not strictly enforced for small or casual use, but "expected" for larger or commercial projects and redistributed collections.
- Prohibited: scraping or bulk downloading beyond the site's download feature; rehosting or mirroring the database (or large parts) as a competing service without written permission; removing attribution when redistributing; anything that breaks Blizzard's terms or IP.
- Rate limit: 120 requests/min per IP anonymous; free key gives 600/min (request it by email contact@hsbg.cards or Telegram/Discord). 429 includes `Retry-After`. The api-docs page recommends caching around one hour and using batch endpoints.
- Commercial: the Terms do not say "non-commercial only", but credit is expected for commercial use. Our app is free and open source, so low risk.
- Runtime download with a disk cache: not forbidden, and the docs encourage caching. **Bundling their images inside our repo or app is the grey zone**: that is redistribution of Blizzard art plus their renders, and "bulk downloading" is prohibited. A full prefetch of every card also looks like scraping.
- Not verified: no explicit statement on tribe/tier icon licensing, no explicit statement about open-source redistribution of their assets, no SLA. Ask by email if we want certainty.

## 3. Proposed minimal design (not implemented)

Principle: the overlay must work fully offline with today's rendering. Remote art is an upgrade only.

1. **Tier badges and tribe icons: draw our own.** No official icon endpoint, and the tier PNGs are Blizzard art served from an undocumented path. Recommend vector badges drawn in code (SwiftUI Shape / SF Symbols for tribes such as `hare` Beast, `ladybug`/`flame` Demon, `gearshape` Mech, `drop` Murloc, `skull` Undead, `water waves` Naga, `flag`/`anchor` Pirate, `flame`/`bolt` Elemental, `pawprint`...; pick per readability), plus a number inside a coloured tier badge. Ships in the repo, zero licensing risk, no network. This keeps the current emoji/number rendering as the fallback and can simply replace it. Optionally later: opt-in download of `/tiers/TierN.png` at runtime only (7 files, about 50 KB), never committed.
2. **Minion images for the next-opponent card: runtime download, disk cache.** On a minion's first display, resolve by card id: `GET /cards?identifiers=...` (batch, one request for a whole board, uses `externalId`/dbf id from Power.log, to be verified), then `GET {image}` (WebP, follows the 302). Store under `~/Library/Application Support/<app>/hsbg-cache/` as `images/{id}.webp` plus `cards.json` (id, tier, minionTypes, fetchedAt, ETag/Last-Modified if the server sends one). Use `URLSession` with `If-None-Match`/`If-Modified-Since` for static files; for JSON use a TTL (24 h, matching their `s-maxage`) since no ETag was seen. Image URLs are immutable per `max-age=86400, immutable`; patches can change art, so re-check weekly or when `updatedAt` differs.
3. **Limits in code:** a single in-flight queue, at most about 30 requests/min (a quarter of the cap), stop on 429 and honour `Retry-After`, no prefetching of the whole database, lazy fetch only for cards actually shown. A User-Agent such as `hsbg-mac-overlay/<version> (github url)` so the maintainer can identify us.
4. **Offline fallback:** any failure (no network, 404, 429, decode error) renders the existing emoji/number view; negative results are cached for a few hours to avoid retry storms.
5. **Tribe mapping from Power.log.** Power.log gives the race as a tag value (`CARDRACE`) or via card data; map the enum names to our icon keys and to hsbg.cards `minionTypes` strings: BEAST->Beast, MURLOC->Murloc, DEMON->Demon, MECHANICAL->Mech, UNDEAD->Undead, NAGA->Naga, DRAGON->Dragon, PIRATE->Pirate, ELEMENTAL->Elemental, QUILBOAST->Quilboar, ALL->All (wildcard; show a special "all tribes" icon), plus ABERRATION if the log uses it. Unknown or missing value shows no icon. Note `minionTypes` is an array (dual-tribe minions), so the UI should support more than one icon. The numeric tag value to name table already lives in our code; the exact names in the log were not checked here.
6. **Attribution:** add "Card data and images courtesy of HS BG Cards (https://hsbg.cards). Hearthstone art is (c) Blizzard Entertainment; not affiliated" to the README and the in-app About/menu.

## 4. Open questions / risks for Dylan

- Own vector icons (my recommendation, confidence high) versus downloading their tier PNGs at runtime. Which look do you want?
- Is showing Blizzard card art in an open-source app acceptable to you? The site's terms allow community projects, but Blizzard's own IP rules are the real limit; a short email to contact@hsbg.cards would settle it.
- Next-opponent card: fetch images only for the 7 current minions of the opponent's last board (lazy, tiny volume, fits 120/min easily), or nothing at all if you want zero network use.
- Dependency risk: the API is a hobby project run by one person, hosted out of pocket; the tier asset paths are undocumented. Hence the fallback requirement.
- Unverified: whether lookup by Hearthstone `externalId` (e.g. `BGS_115`) works for Power.log ids; whether JSON endpoints ever return ETag; behaviour at 429; whether the free key is worth requesting (not needed at our volume).
- Privacy: requests expose the user's IP to hsbg.cards (their privacy policy says anonymous Umami analytics, no cookies). Mention it in the README, and consider an off switch in the menu.
