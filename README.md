# HSBG Mac Overlay

[![CI](https://github.com/dylanbuchi/hsbg-mac-overlay/actions/workflows/ci.yml/badge.svg)](https://github.com/dylanbuchi/hsbg-mac-overlay/actions/workflows/ci.yml)

A free macOS overlay for Hearthstone Battlegrounds. It labels every leaderboard portrait with the player's name, MMR, tavern tier, combat record and streak, and shows a full card for your next opponent (tier pace, last board, triples). It runs alongside [HSTracker](https://hsdecktracker.net/hstracker/), which doesn't show these on the leaderboard.

Battlegrounds **Solo** only, macOS only. Not affiliated with Blizzard Entertainment or HearthSim.

> **Use at your own risk.** This app reads Hearthstone's memory through HSTracker's HearthMirror component, loaded from your HSTracker installation (found by its bundle id, `/Applications/HSTracker.app` by default), and is signed with the `com.apple.security.cs.debugger` entitlement to do so. Blizzard's Terms of Use prohibit unauthorized third-party programs that read game data; Blizzard has historically tolerated deck trackers, but that is not a guarantee, and your account is your responsibility. The app never injects code, automates input, or changes game files. See [Data sources and risk](#data-sources-and-risk).

<p align="center">
  <img src="docs/overlay-tier-icons.png" width="260" alt="Leaderboard with nameplates, tier shields, records, streaks, tribes and level turns; player names hidden">
  &nbsp;&nbsp;
  <img src="docs/overlay-tier-numbers.png" width="230" alt="The same labels with colored tier numbers instead of shields; player names hidden">
</p>
<p align="center"><sub>Tier shields (left) or colored tier numbers (right). Player names are hidden in these screenshots.</sub></p>

## Reading the overlay

The same guide is in the app: menu bar **BG → How to Read the Overlay…**

| Label | Meaning |
|---|---|
| Name, then MMR | Player name, and under it their rating from the public leaderboard (gold). **—** means no public rating: usually below 8,000 (only the top of each region is published), sometimes a recent rename or a name shared by two leaderboard players. A gold diamond before the MMR is the highest rating in the lobby; a small blue dot after the name is you. |
| `10-1` | Rounds not lost, then rounds lost. Ties count as not lost (nobody takes damage, so the log cannot tell them from wins). |
| ▲ 4 / ▼ 3 | 2 or more rounds in a row **not lost** (▲, amber) or **lost** (▼, blue), and how many. The arrow says which, so colour is never the only clue. |
| Round icon + number | Under the tier shield: their main tribe (own simple icon per tribe: Beast, Demon, Dragon, Elemental, Mech, Murloc, Naga, Pirate, Quilboar, Undead, Aberration; Amalgam counts for every tribe) and how many minions of it on the last board you saw them play. A second tribe shows at 3 or more. Faded when that board is more than 2 turns old. |
| Shield or colored number | Tavern tier. Shields show stars; numbers are grey 1, green 2, blue 3, purple 4, orange 5, red 6. |
| ◆◆◆ 2 | Triples made this game (here, 2), under the MMR; shown once they have at least one. |

The label is a soft dark fade with outlined type over the top of the portrait, and scales with the window. On small windows it drops the record first, then the streak, so name and MMR always stay readable.

### Next opponent card

During the shop phase, a **NEXT OPPONENT** card sits on the left, under HSTracker's panel (the overlay finds HSTracker's window by its position and size only; it never reads its title or contents, so no screen-recording permission is needed). HSTracker usually draws its panel inside one big transparent window, whose real bottom edge cannot be measured from outside; in that case (the usual one) the card sits at the lower left of the game window, 60 % of the way down, which clears a "Latest Games" list of up to about 8 rows. The card shrinks to fit above the bottom edge, and is hidden if there is no room at all. It shows:

- their name, MMR and rank among the listed players of the lobby (`#2 of 5 listed`);
- record and streak (▲ not lost / ▼ lost);
- tier pace: the tier they are at and the turn they reached it (`T5 on turn 8`);
- last board: main tribe and how many of it, board size and highest tier, from the last time you fought them (faded when more than 2 turns old);
- triples.

A **—** means unknown (never a guess): for example no MMR when they are not on the public leaderboard, or no last board before you have fought them. There is one card at a time. It hides during combat, after the last fight and when the game names no next opponent.

Menu options: **Tier Icons** (shields or numbers), **Hide During Combat** (labels follow the fight animation, so showing them is safe), **MMR Region** (EU, US or AP; remembered). The first menu line shows what the overlay currently sees, which helps when nothing appears. Below it, once ratings are known, a second line summarizes the lobby, for example `Lobby avg 9.4k · you #3 of 5 listed · 3 unlisted`: the average of the players who have a public rating, your rank among them, and how many players have none (unlisted players are counted, never guessed; if you are unlisted it says so).

<p align="center"><img src="docs/menu.png" width="420" alt="The BG menu bar menu: status line, Show Overlay, MMR Region, Tier Icons, Hide During Combat, How to Read the Overlay, Quit"></p>

## Requirements

- macOS 13 or later, Apple silicon or Intel
- [HSTracker](https://hsdecktracker.net/hstracker/) installed (anywhere macOS can find it; `/Applications` is the default), for player names and tier shields. Without it the overlay still shows tiers (as numbers), records, streaks and the next-opponent card, but opponents' names, and so their MMR, are missing (the log only names you).
- Hearthstone writing verbose Power logs (below)

### Enable Power logging

Create or edit `~/Library/Preferences/Blizzard/Hearthstone/log.config` so it contains:

```
[Power]
LogLevel=1
FilePrinting=true
ConsolePrinting=false
Verbose=true
```

Or open the **BG** menu and choose **Turn On Power Logging…**, which makes this change for you (the old file is kept as `log.config.bak`; the item only shows when logging is not already on). Then restart Hearthstone. Logs are written to the `Logs` folder next to `Hearthstone.app` (`/Applications/Hearthstone/Logs` by default). If you already use HSTracker, this is usually set up.

## Install

1. Download `HSBG-Mac-Overlay.zip` from the [latest release](https://github.com/dylanbuchi/hsbg-mac-overlay/releases/latest). It is built by GitHub Actions from the tagged source ([workflow](.github/workflows/release.yml)).
2. Unzip it and move **HSBG Mac Overlay** to your Applications folder.
3. Open it. The app is free and not notarized by Apple, so macOS blocks the first launch: click **Done**, then open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to HSBG Mac Overlay. On macOS 13 or 14 you can instead right-click the app and choose **Open**. This is needed only once. Terminal alternative: `xattr -dr com.apple.quarantine "/Applications/HSBG Mac Overlay.app"`.

The app appears in the menu bar as **BG**; it has no window or Dock icon. The first launch opens the "How to Read the Overlay" guide so you know it is running. macOS may ask for permission ("Developer Tools Access") the first time the app reads names from Hearthstone; on a standard (non-admin) account it can ask for an administrator password. Declining keeps the overlay working from the log alone. To start it automatically, add it in **System Settings → General → Login Items**.

### Verify the download

Releases carry a build provenance attestation made by GitHub Actions. The commands look for the files in the current folder, so first go to where you saved them (for example the Downloads folder). With the [GitHub CLI](https://cli.github.com/):

```bash
cd ~/Downloads
gh attestation verify HSBG-Mac-Overlay.zip --owner dylanbuchi
```

## Troubleshooting

The first line of the **BG** menu says what the overlay sees.

| Status | What to do |
|---|---|
| No Power.log yet | Power logging is off. Choose **Turn On Power Logging…** in the BG menu (or edit `log.config` as above), then restart Hearthstone. |
| Reading Power.log… NN% | Normal after a long session: the log is read in pieces. It finishes by itself. |
| Log connected · waiting for a Battlegrounds Solo match | Working. Start a Solo match. |
| Duos is not supported yet | Duos is not supported; play Solo. |
| no names: HearthMirror framework unavailable / could not load HearthMirror | Install [HSTracker](https://hsdecktracker.net/hstracker/). The overlay still works from the log, without opponent names or MMR. |
| no names: HSTracker is missing or its signature is not HearthSim's | The app only loads HearthMirror from HearthSim's signed HSTracker. Reinstall the official release; self-built copies are refused. |
| no names: task_for_pid denied | macOS refused access to Hearthstone. Allow the macOS prompt if one appears, then reopen the overlay. |
| MMR offline, retrying | No leaderboard source could be reached and there is no recent cache; it retries every 30 s to 2 min by itself. |
| MMR … via cache, NN min old | Every source failed, so the last saved list (under 6 hours old) is used; live sources are retried automatically. |
| Reading the game stalled | The reader is stuck. Quit and reopen the overlay. |

If nothing helps, open an issue and paste the first line of the menu, plus the version (the **BG** menu shows it at the bottom, and **About HSBG Mac Overlay** opens the standard About panel).

## Build from source

Requires Xcode 16 or later (Swift 6 tools).

```bash
swift build
swift test
```

Build a Finder-launchable app bundle (ad-hoc signed with the debugger entitlement) into `dist/`:

```bash
sh scripts/package-app.sh
```

Or install it to `~/Applications` and start it at login (it shows the overlay whenever Hearthstone is open):

```bash
sh scripts/install-autostart.sh
```

`swift run HSBGMacOverlay` also works for development, but that binary lacks the debugger entitlement, so it runs on the log alone (no opponent names or MMR).

### Uninstall

If you downloaded the app, quit it from the **BG** menu, remove it from Login Items if you added it, and delete it from Applications. If you used `install-autostart.sh`:

```bash
launchctl bootout gui/$(id -u)/com.dylanbuchi.hsbg-mac-overlay
```

Run `defaults delete com.dylanbuchi.hsbg-mac-overlay` to clear its preferences. Then delete `~/Library/LaunchAgents/com.dylanbuchi.hsbg-mac-overlay.plist`, `~/Applications/HSBG Mac Overlay.app`, `~/Library/Application Support/HSBGMacOverlay` (the ratings cache) and `~/Library/Logs/HSBGMacOverlay*.log`.

## Data sources and risk

1. **`Power.log` (read-only).** Leaderboard places, heroes, tavern tiers, triples, health changes, the next opponent and the boards you fight. Board state is read from playback (`PowerTaskList`) lines so it changes with the animation; game type, names and game boundaries come from `GameState` lines.
2. **HearthMirror (reads game memory).** `HearthMirrorBridge` loads the framework from the installed HSTracker at runtime, after checking that the app is HearthSim's signed build, and attaches to the Hearthstone process to read the lobby (player names). It runs about once a second while Hearthstone is open and a Power.log exists. HearthMirror is not bundled; without HSTracker, the overlay uses the log only.
3. **Leaderboard lists (network).** Public copies of Blizzard's Battlegrounds leaderboard, tried in order: [bgrank.fly.dev](https://bgrank.fly.dev) (an unofficial mirror), then a GitHub mirror of the same list ([bg-board-mirror](https://github.com/lowerman/bg-board-mirror), refreshed about every 30 minutes). The app downloads the list for your region (EU by default) when a new game starts (at most every 2 minutes) and every 15 minutes during a game, and matches names locally; after a failure it retries after 30 s, 60 s, then every 2 minutes. A source that is down, answers with an error or returns too few rows is skipped. The last good list is kept in `~/Library/Application Support/HSBGMacOverlay/` and used only when every source fails; it expires after 6 hours and is validated on load. The status line says which source (or the cache) is in use. Each request is a plain download: like any web request it reveals your IP address and the app's name and version to that server, but it contains no player names or game data. Blizzard's own leaderboard API is not used: it serves 25 players per ~300 KB page, about 300 pages for EU, which is too heavy to poll politely.
4. **GitHub releases (network).** At launch the app makes one anonymous request to `api.github.com` for the latest release of this repository. If a newer version exists, the BG menu gets a "New Version Available" item that opens the release page. Nothing about you or the game is sent beyond what any web request reveals (IP address, app name and version); offline or on any error it stays silent. You can turn it off in Settings (BG menu > Settings…).

5. **Tavern tier badges on the NEXT OPPONENT card (network).** The card shows the game's tier badge. The six images (`Tier1.png` to `Tier6.png`) are downloaded once from [hsbg.cards](https://hsbg.cards/tiers/Tier1.png) the first time a tier is needed (one plain GET each, 8 s timeout, no retry loop) and cached in `~/Library/Application Support/HSBGMacOverlay/tier-images/`; the app asks the server again at most once a day. Images must be real PNGs under 200 KB. Offline or on any error, a drawn badge is used instead. Like any web request, this lets hsbg.cards see your IP address and the app's name and version, nothing else. The images are Blizzard artwork and are not part of this repository or the app. Card data and images courtesy of HS BG Cards; not affiliated with Blizzard.

Tavern tier shields are also read at runtime from the HSTracker app bundle. This repository contains no Blizzard assets and no HearthSim binaries.

## What the overlay shows, and policy

It shows only what a player can also see in the game or on the public leaderboard: names, tavern tiers, boards you fought, triples, and a record derived from watching combats. It never automates input or changes game files. Blizzard's policy can change, and features will be removed if they ask.

## Known limits

- Solo only: in Duos the overlay shows nothing (the menu says so).
- Tribes use each minion's main race only (the log carries one per minion), and exist only for players you have fought.
- MMR results are kept in memory (and a short-lived cache on disk as a last resort); they refresh when a new game starts and every 15 minutes during a game, and the public leaderboard itself can lag a few minutes behind.

## Support

HSBG Mac Overlay is free and open source. If it helps your climb, you can buy me a coffee; it helps me keep it working after Hearthstone patches.

<a href="https://ko-fi.com/dylanbuchi"><img src="https://img.shields.io/badge/Ko--fi-Buy%20me%20a%20coffee-FF5E5B?logo=ko-fi&logoColor=white" alt="Buy me a coffee on Ko-fi"></a>

## License

MIT, see [LICENSE](LICENSE). The leaderboard geometry is derived from HSTracker (MIT, © HearthSim); see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Hearthstone is © Blizzard Entertainment.

## Demo mode (for testing the layout)

Run the app with `--demo` (or `HSBG_DEMO=1`) to open a plain window with a made-up 8-player lobby and a fake HSTracker panel (none, 4, 6 or 10 rows). Use it to check where the Next Opponent card sits. It never reads the game or the network lobby. The menu bar option "Show Next Opponent in Combat" controls whether the card stays visible during fights.
