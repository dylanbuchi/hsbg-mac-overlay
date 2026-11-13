# Changelog

## Unreleased

- **Tavern list on hover**: a row of tier shields 1 to 6 at the top of the empty space right of the board, with your own tier glowing. Point at a tier to see its minions grouped by this lobby's tribes (plus amalgams and minions with no tribe), with attack/health and Battlecry, Deathrattle, Divine Shield, Taunt, End of turn and Reborn tags, and that tier's tavern spells with their gold cost, plus the tribes not in this lobby; point at a card in the list to see it larger. No clicks; it opens in about a millisecond because every tier's list is built once per game. The lobby's tribes come from the built-in reader; if it cannot read them, every tribe is listed. Card data from HearthstoneJSON (built-in snapshot, refreshed at most twice a day). Off switch in Settings.

## 0.2.2 (2026-11-13)

Player names and live tribes are back, read by the overlay itself.

- **Built-in game reader**: HSTracker 3.7.4 locked its HearthMirror reader to HSTracker only, so names, MMR and the NEXT OPPONENT card had stopped. The overlay now reads player names with its own small read-only reader: it only copies memory out of the game (no writes, no injection), keeps names in memory only, and never loads HearthMirror. macOS asks for an administrator password the first time ("Developer Tools Access"). Apple silicon, with Hearthstone not under Rosetta.
- Names are matched to Power.log players by PLAYER_ID, which is exact (no more matching through heroes).
- HSTracker is now optional: only for the tier shields, the round tribe pictures and docking the card under its panel.
- Live opponent tribes are back, through the same built-in reader (the counts the game shows on a leaderboard hover).
- Fix: after Hearthstone was quit in the middle of a match and opened again, the old match stayed on screen over the menu until the next game started.
- Credits: the reader follows Firestone's unity-spy and hackf5/unityspy (MIT), see NOTICE.

## 0.2.1 (2026-11-10)

Trinkets, a Dark Gifts counter and a fix for names on the wrong player.

- **Opponent trinkets on the NEXT OPPONENT card**: the lesser and greater trinket as small cards at the top right, read from Power.log as the game shows them on the leaderboard. Point at one for a larger copy with its full text, like the minions. Names and art come from hsbg.cards, cached on disk.
- **Dark Gifts counter**: in Dark Gifts lobbies, a small `DARK GIFTS 2 left` box under the Dark Discovery button counts the Dark Discoveries you can still use this game (3 per game, read from Power.log). It grows with the window and hides once all are used, in combat (with the labels) and in other lobbies.
- **Names no longer land on the wrong player**: each name now goes to one player only (exact hero first, then the hero without its skin). A player whose name cannot be matched keeps a tier-only label instead of borrowing someone else's.
- **Diagnostics log**: name matching problems are written to `~/Library/Logs/HSBGMacOverlay/overlay.log` (no player names, at most two files of 256 KB), so a bug seen in play can be checked later.
- The last fight of a game is now counted in records and streaks (it was dropped because the game ends before the shop returns). Not visible yet, since the overlay hides at game over.
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
