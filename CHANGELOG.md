# Changelog

## Unreleased

- **Opponent trinkets on the NEXT OPPONENT card**: the lesser and greater trinket as small cards at the top right, read from Power.log as the game shows them on the leaderboard. Point at one for a larger copy with its full text, like the minions. Names and art come from hsbg.cards, cached on disk.
- **Dark Gifts counter**: in Dark Gifts lobbies, a small `DARK GIFTS 2 left` box on the right edge counts the Dark Discoveries you can still use this game (3 per game, read from Power.log). It hides once all are used, in combat (with the labels) and in other lobbies.
- **Names no longer land on the wrong player**: each name now goes to one player only (exact hero first, then the hero without its skin). A player whose name cannot be matched keeps a tier-only label instead of borrowing someone else's.
- **Diagnostics log**: name matching problems are written to `~/Library/Logs/HSBGMacOverlay/overlay.log` (no player names, at most two files of 256 KB), so a bug seen in play can be checked later.
- About window: shorter credits, link visible.

## 0.2.0 (2026-11-02)

New look and a card for your next opponent. Folds the unreleased 0.1.2 to 0.1.4 work.

- **Portrait labels redesigned** ("Edge Ink"): a dark fade over the top of each portrait with outlined name, MMR, record and streak. ▲ is a run not lost, ▼ a run lost, so colour is never the only clue. The highest MMR in the lobby is a brighter, bolder gold. Labels scale with the window, drop the record then the streak on small windows, and appear only once a player is on the leaderboard. Triples show as a gold disc and a count.
- **NEXT OPPONENT card** during the shop phase, under HSTracker's panel or at the bottom left: name, MMR with its change since an older leaderboard list (`▲45`, `since 6 h`), record and streak, tier and the turn they reached it, tribes, last board, health and armor with the damage they last took, triples with their turns, and your latest fights against them. Unknown values are left out or shown as a dash, never guessed. Hidden in combat unless "Show Next Opponent During Combat" is on.
- **Live opponent tribes** read from game memory (the counts the game shows when you hover a portrait), through HSTracker's HearthMirror, read only, Apple silicon. Labelled `live`, else `seen turn N` from your last fight. Types with a single minion are left out. Settings has an off switch.
- **Tribe icons**: the round pictures from your installed HSTracker (loaded at runtime, never copied), else our own drawn icons.
- **Last board as minion cards**, with art from hsbg.cards downloaded at runtime and cached on disk. Point at a minion and a larger copy appears just above it.
- **Move and resize the card**: point at it for a gold grip and corner, or use "Move Card…". Saved per window shape; "Reset Card Position" goes back to automatic.
- **Tier badges** on the card from hsbg.cards (cached, drawn fallback).
- **Reconnects**: tier and triple turns replayed after a reconnect stay unknown instead of showing the reconnect turn.
- **MMR**: falls back to a GitHub mirror, then to a cached list (6 h); the menu shows the lobby average, your rank among listed players and how many are unlisted.
- **App**: new "BG" icon, About panel, version line, a Settings window (launch at login, update check, memory reading, minion zoom), and a hidden `--demo` mode with a made-up lobby for checking the layout.

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
