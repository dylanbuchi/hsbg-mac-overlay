# Changelog

## 0.1.4 (unreleased)

- New "BG" app icon (original artwork, full-bleed so macOS masks it once). `scripts/make-icon.sh` rebuilds the icns from `packaging/AppIcon-master.png`.
- The Settings window (BG menu > Settings…, ⌘,) is no longer empty: "Launch at login" (macOS may ask for approval or refuse this ad-hoc signed app; the window says why and how to add it by hand), "Check for updates automatically" (default on), and the version and build.

## 0.1.3 (unreleased)

- New option "Show Next Opponent in Combat" in the menu bar menu (off by default, remembered).
- Hidden demo mode for checking the layout without playing: launch with `--demo` (or `HSBG_DEMO=1`). It uses a made-up lobby and a fake HSTracker panel; it does not read the game.
- The Next Opponent card now narrows to stay clear of the leaderboard labels.

- Portrait labels redesigned ("Edge Ink"): a soft dark fade at the top of each portrait with outlined type for name, MMR, record and a streak. ▲ is a run not lost, ▼ a run lost, so colour is never the only clue. It scales with the window and drops the record, then the streak, on small windows. The highest MMR in the lobby is shown in a brighter, bolder gold and a blue dot marks you.
- New permanent NEXT OPPONENT card during the shop phase, docked under HSTracker's left panel (found by window position and size only; fallback, which is the usual case because HSTracker draws its panel inside one big window: lower left of the game window, 60 % down, shrinking or hiding rather than overlapping): name, MMR and lobby rank, record and streak, tier pace, last board, triples. Unknown values show a dash. Hidden in combat, after the last fight and when there is no next opponent.
- Tribes are back on the portrait, under the tier shield, as original round icons (one glyph and colour per tribe, no emoji) with a minion count; at most two.
- The chips beside portraits (flame, tribe emoji, level turn) are gone; that information is on the card. Triples stay on the portrait label (three diamonds and a count).
- The NEXT OPPONENT card shows their tavern tier badge: the game's image, downloaded once per tier from hsbg.cards (7 KB each, cached on disk, rechecked at most daily, validated as PNG under 200 KB, never bundled), with the drawn tier badge as fallback while loading, offline or on any error.
- Lost-streak and last-board (size, highest tier) data are now tracked.

## 0.1.2 (unreleased)

- MMR: if bgrank.fly.dev is down, the list comes from a GitHub mirror; the last good list is cached on disk (6 h, validated) as a last resort, and the status line says which source is used.
- App icon (original artwork), shown in Finder and the About panel.
- Menu line with the lobby average MMR, your rank among listed players, and how many players are unlisted.
- About panel and version line in the BG menu; the version also appears in error statuses.

## 0.1.1 (2026-10-31)

- Power.log is read and parsed off the main thread, in 8 MB chunks, with a progress status while catching up; a replaced or truncated log restarts cleanly.
- MMR download retries after 30 s, 60 s, then every 2 minutes after a failure; the status line says "MMR offline, retrying". Ratings match names that carry a `#1234` suffix.
- HSTracker and Hearthstone are found by bundle id and the running app, not only in `/Applications`. HSTracker's signature is verified before HearthMirror is loaded.
- Timers keep running while a menu is open; full-screen detection tolerates notch and scaled displays; unplaced players no longer share a portrait.
- "Turn On Power Logging…" menu item, first-launch guide, and an update check at launch (one anonymous request to GitHub; see the README).
- Tags addressed to a name shared by several players are ignored instead of guessed.
- CI on every push, build provenance on releases, README troubleshooting.

## 0.1.0

First release.
