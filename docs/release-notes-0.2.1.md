# HSBG Mac Overlay 0.2.1

## What's new

- **Opponent trinkets on the NEXT OPPONENT card.** Their lesser and greater trinket appear as small cards at the top right once picked. Point at one to see it larger with its full text.
- **Dark Gifts counter.** In Dark Gifts lobbies, a small `DARK GIFTS 3 left` box under the Dark Discovery button shows how many Dark Discoveries you can still use this game. It hides once all three are used.
- **Names stay on the right player.** Each name now goes to one player only. If a name cannot be matched, that portrait shows its tier without a name instead of someone else's.
- **Diagnostics log** in `~/Library/Logs/HSBGMacOverlay/overlay.log` for name matching problems (no player names), so a bug seen in play can be checked later. Mention it in bug reports.
- Records and streaks now include the last fight of a game.

## First launch: the app is not notarized

If this is your first install, macOS blocks the first launch:

1. Unzip `HSBG-Mac-Overlay.zip` and move **HSBG Mac Overlay** to Applications.
2. Open it. When macOS says it cannot check the app, click **Done**.
3. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to HSBG Mac Overlay.

Updating from 0.2.0: quit the old app from the **BG** menu, replace it in Applications, and open the new one. macOS may ask once again to allow it.

## Requirements

- macOS 13 or later. Apple silicon for live tribes; the rest also runs on Intel.
- [HSTracker](https://github.com/HearthSim/HSTracker) installed, for player names, MMR and live tribes.
- Hearthstone Power logging on (BG menu → **Turn On Power Logging…**).
- Battlegrounds Solo only.

## Privacy

Unchanged from 0.2.0: game memory is read only through HSTracker's HearthMirror and never saved or sent. The app talks to the same four https hosts; trinket names and art come from hsbg.cards, looked up by card id only. The new diagnostics log stays on your Mac and holds no player names.

## Known limits

- Solo only, no Duos.
- The Dark Gifts counter reads a value on the game's Dark Discovery button; a game update could change it. Opponents' Dark Gifts are not in the log, so they are not shown.
- A Hearthstone or HSTracker update can stop the memory reads (names, live tribes) until the app is updated; it then falls back to the log.
- Blizzard's terms forbid unauthorized programs that read game data. Deck trackers have been tolerated, but use it at your own risk.

## Verify the download

```bash
cd ~/Downloads
gh attestation verify HSBG-Mac-Overlay.zip --owner dylanbuchi
```
