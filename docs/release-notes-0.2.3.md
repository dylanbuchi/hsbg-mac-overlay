# HSBG Mac Overlay 0.2.3

## What's new

- **Tavern list.** In the shop, a row of tier shields 1 to 7 sits beside the board. Click a tier to see every minion and spell it can offer in this lobby, grouped by the lobby's tribes, with attack/health, keyword tags and spell costs. Click it again to close it. Point at a card to see it larger. Tier 7 is there too, marked "only in some games".
- **Filter.** The funnel left of tier 1 narrows every tier by card type, keyword (Battlecry, Deathrattle, Avenge, Rally, Start of Combat...) or synergy read from the card text (Discover, Gold, Blood Gems, spells, Refresh), with counts for this lobby.
- **Open my tier's list** (Settings, off by default): each shop opens the list of the tier you are on and follows you up.
- **Card art is more reliable.** Art is looked up by card id when a name has a comma, a network hiccup retries after 30 seconds instead of 10 minutes, and the cache holds 600 images.

The click on a tier shield still reaches the game: the overlay never takes or sends input.

## Install or update

1. Unzip `HSBG-Mac-Overlay.zip` and move **HSBG Mac Overlay** to Applications. When updating, quit the old app from the **BG** menu first.
2. The app is not notarized. macOS blocks the first launch: click **Done** (macOS 15 and later; on macOS 13 or 14, right-click the app, choose **Open** and you are done), then open **System Settings → Privacy & Security** and click **Open Anyway** next to HSBG Mac Overlay. macOS asks again after each update, since each download is new to it.

## Requirements

- macOS 13 or later. Player names, live tribes and the lobby's tribes in the tavern list need Apple silicon, with Hearthstone not under Rosetta; elsewhere the list shows every tribe.
- Hearthstone Power logging on (BG menu → **Turn On Power Logging…**).
- Battlegrounds Solo only.
- Optional: [HSTracker](https://github.com/HearthSim/HSTracker), for the tier shields, round tribe pictures and docking the card.

## Privacy

One new host: the card pool comes from [HearthstoneJSON](https://hearthstonejson.com) (CC0), checked at most every 12 hours. A built-in copy means the list works offline. Card art still comes from hsbg.cards, by card name or id only. Player names stay in memory and are never saved, logged or sent.

## Known limits

- Solo only, no Duos.
- A Hearthstone update can stop the memory reads until the app is updated; the list then shows every tribe.
- Blizzard's terms forbid unauthorized programs that read game data. Deck trackers have been tolerated, but use it at your own risk.

## Verify the download

```bash
cd ~/Downloads
gh attestation verify HSBG-Mac-Overlay.zip --owner dylanbuchi
```
