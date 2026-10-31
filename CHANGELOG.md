# Changelog

## Unreleased

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
