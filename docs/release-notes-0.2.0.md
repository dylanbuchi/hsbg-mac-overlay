# HSBG Mac Overlay 0.2.0 (draft, not published)

## First launch: the app is not notarized

The app is free and not notarized by Apple, so macOS blocks it the first time:

1. Unzip `HSBG-Mac-Overlay.zip` and move **HSBG Mac Overlay** to Applications.
2. Open it. When macOS says it cannot check the app, click **Done**.
3. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to HSBG Mac Overlay.
4. On macOS 13 or 14 you can instead right-click the app and choose **Open**.

You only do this once. macOS may also ask for "Developer Tools Access" the first time the app reads player names; declining keeps the overlay working from the log alone.

## What's new

- **New labels on the portraits.** Name, MMR, record and streak in outlined type over a soft dark fade. ▲ means a run not lost, ▼ a run lost. The top MMR in the lobby is a brighter gold.
- **A card for your next opponent** during the shop phase: their MMR and how it moved, record, tier and when they got there, tribes, last board, health and armor, triples and your last fights against them.
- **Live opponent tribes**, the same counts the game shows when you hover a portrait, read from game memory (Apple silicon). You can switch it off in Settings.
- **Last board as small minion cards.** Point at one to see it larger, just above it.
- **Move and resize the card**: point at it and drag the gold grip or corner. "Reset Card Position" puts it back.
- **More reliable MMR**: a backup mirror and a short cache when the main source is down.
- Safer after a reconnect, a Settings window, a new icon, and an About panel.

## Requirements

- macOS 13 or later.
- Apple silicon for live tribes. The rest also runs on Intel.
- [HSTracker](https://hsdecktracker.net/hstracker/) installed, for player names, MMR and live tribes.
- Hearthstone Power logging on (BG menu → **Turn On Power Logging…**).
- Battlegrounds Solo only.

## Privacy

The app reads game memory only through HSTracker's HearthMirror and only reads: player names, heroes and account ids for the lobby order, and the leaderboard's tribe counts. None of it is saved or sent. It talks to three https services (leaderboard lists, GitHub for updates, hsbg.cards for card images) and sends no player data.

## Known limits

- Solo only, no Duos.
- A Hearthstone or HSTracker update can stop the memory reads (names, live tribes) or crash the app until it is updated; it then falls back to the log.
- After a reconnect, records and streaks restart from that point, and earlier tier and triple turns are unknown.
- Blizzard's terms forbid unauthorized programs that read game data. Deck trackers have been tolerated, but use it at your own risk.

## Verify the download

```bash
gh attestation verify HSBG-Mac-Overlay.zip --owner dylanbuchi
```
