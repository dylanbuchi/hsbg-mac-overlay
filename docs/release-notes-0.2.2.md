# HSBG Mac Overlay 0.2.2

## What's new

- **Player names are back, read by the overlay itself.** HSTracker 3.7.4 locked its game reader to HSTracker only, so names, MMR and the NEXT OPPONENT card stopped working in 0.2.1. The overlay now has its own small reader: it only copies data out of the game (no writes, no injection, nothing automated) and never loads HSTracker's reader.
- **Live opponent tribes are back** through the same reader: the counts the game shows when you hover a portrait, refreshed every few seconds.
- **Names are matched by the game's player number**, which is exact, instead of through heroes.
- **HSTracker is now optional.** It is only used for the tier shields, the round tribe pictures and docking the card under its panel.
- **Fix:** after Hearthstone was quit in the middle of a match and opened again, the old match stayed on screen over the menu.

## First launch: the app is not notarized

If this is your first install, macOS blocks the first launch:

1. Unzip `HSBG-Mac-Overlay.zip` and move **HSBG Mac Overlay** to Applications.
2. Open it. When macOS says it cannot check the app, click **Done** (macOS 15 and later; on macOS 13 or 14, right-click the app, choose **Open** and you are done).
3. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to HSBG Mac Overlay.

Updating from 0.2.1: quit the old app from the **BG** menu, replace it in Applications, and open the new one. macOS will ask once again to allow it, since each download is new to it.

The first time the overlay reads the game, macOS may ask for permission ("Developer Tools Access"), with an administrator password on a standard account. That is the standard prompt for apps that read another process. Declining keeps the overlay working from the log alone.

## Requirements

- macOS 13 or later. Player names and live tribes need Apple silicon, with Hearthstone not opened under Rosetta; the rest also runs on Intel.
- Hearthstone Power logging on (BG menu → **Turn On Power Logging…**).
- Battlegrounds Solo only.
- Optional: [HSTracker](https://github.com/HearthSim/HSTracker), for the tier shields, round tribe pictures and docking the card.

## Privacy

The reader only copies data out of Hearthstone. Names and account ids stay in memory: they are never saved, logged or sent. The diagnostics log holds hero ids and places only. The app talks to the same https hosts as 0.2.1.

## Credits

The reader follows the approach of Firestone's unity-spy and hackf5/unityspy (both MIT); see NOTICE.

## Known limits

- Solo only, no Duos.
- A Hearthstone update can stop the memory reads (names, live tribes) until the app is updated; it then falls back to the log.
- Blizzard's terms forbid unauthorized programs that read game data. Deck trackers have been tolerated, but use it at your own risk.

## Verify the download

```bash
cd ~/Downloads
gh attestation verify HSBG-Mac-Overlay.zip --owner dylanbuchi
```
