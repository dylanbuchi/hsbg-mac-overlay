# HSBG Mac Overlay

A native macOS companion for Hearthstone Battlegrounds, built for personal use. It labels every leaderboard portrait with the player's MMR, tavern tier, combat record, streak, triples, main tribe and levelling pace.

The app runs alongside HSTracker. It never injects code into Hearthstone, automates input, or modifies game files, but it does read game memory through HSTracker's HearthMirror (see [Data sources and risk](#data-sources-and-risk)).

## Reading the overlay

The same guide is in the app: menu bar **BG → How to Read the Overlay…**

| Label | Meaning |
|---|---|
| Name over number | Player name and rating from the public leaderboard. **—** means no public rating: usually below 8,000 (only the top of each region is published), sometimes a recent rename or a name shared by two leaderboard players. |
| Shield or colored number | Tavern tier. Shields show stars; numbers are grey 1, green 2, blue 3, purple 4, orange 5, red 6. |
| `10-1` | Rounds not lost, then rounds lost. Ties count as not lost (nobody takes damage, so the log cannot tell them from wins). |
| Flame `4` | 2 or more rounds in a row without losing. |
| Tribe icon `5` (e.g. 🐉 5) | Main tribe on their board the last time you fought them, and how many; a second tribe shows at 3 or more. Faded when more than 2 turns old. |
| Sparkles `2` | Triples made this game. |
| Up arrow `9` | Turn they reached their current tier; low means fast levelling. |
| Pushed-out portrait | Your next opponent; labels move with it. |

Tribe icons: 🐾 Beast · 😈 Demon · 🐉 Dragon · 🌪️ Elemental · ⚙️ Mech · 🐟 Murloc · 🐍 Naga · 🦜 Pirate · 🐗 Quilboar · 💀 Undead · 👁️ Aberration · 🌈 Amalgam (every tribe).

Menu options: **Tier Icons** (shields or numbers), **Hide During Combat** (labels follow the fight animation, so showing them is safe), **MMR Region** (EU, US or AP).

## Current status

Working personal tool:

- Swift Package Manager project with a menu-bar app identity
- floating overlay over the Hearthstone content area: a nameplate (name over MMR) across the top of each leaderboard portrait, a tavern tier shield or badge beside it, and record, streak, tribe, triples and level-turn chips under it
- tier shields are loaded at runtime from the installed HSTracker (Blizzard art is not bundled); without it the colored numbers are used
- slot positions follow HDT's leaderboard geometry (`LeaderboardLayout`, as ported to HSTracker, MIT, © HearthSim), scale with the window, and follow the next opponent's pushed-out portrait
- overlay shows only while Hearthstone is running and focused; labels hide in menus and after the game, and optionally during combat
- read-only `Power.log` tailing: board state from playback (`PowerTaskList`) lines so it changes with the animation, game type, names and boundaries from `GameState`
- live lobby names from HearthMirror, matched to heroes and sorted by leaderboard place
- optional opponent MMR lookup from a selectable US, EU, or AP BGrank mirror, refreshed at most every 15 minutes
- Finder-launchable `.app` packaging and a login autostart installer

## Open items

1. MMR results live only in memory: add a disk cache and a visible stale-data state.
2. Solo only: Duos leaderboard spacing is not implemented.
3. Tribes use each minion's main race only (the log carries one per minion), and exist only for players you have fought.

## Data sources and risk

The overlay combines three sources:

1. **`Power.log` (read-only).** Leaderboard places, heroes, Tavern Tiers, the next opponent (`NEXT_OPPONENT_PLAYER_ID` on the local player entity), and combat playback (`PowerTaskList` lines mark when the combat animation starts and ends). Hearthstone must write verbose Power logs: enable the Power section in `~/Library/Preferences/Blizzard/Hearthstone/log.config`, then restart Hearthstone.
2. **HearthMirror (reads game memory).** `HearthMirrorBridge` loads the framework from `/Applications/HSTracker.app` at runtime and attaches to the Hearthstone process to read the Battlegrounds lobby. The packaged app is signed with the `com.apple.security.cs.debugger` entitlement so it can do this. HearthMirror is not bundled; without HSTracker at that path, the overlay falls back to `Power.log` only.
3. **BGrank (public network lookup).** MMR is matched against names already present locally. If the lookup fails, local data keeps working.

Memory reading is the same technique HSTracker uses, but it carries more account risk than log-only tools. Blizzard's third-party tool rules can change, so this is not meant to be distributed.

## Build

```bash
swift build
swift test
swift run HSBGMacOverlay
```

To build a Finder-launchable app bundle (ad-hoc signed with the debugger entitlement):

```bash
sh scripts/package-app.sh
```

To install it as a menu-bar companion that starts at login, opens with Hearthstone, and closes its overlay when Hearthstone quits:

```bash
sh scripts/install-autostart.sh
```
