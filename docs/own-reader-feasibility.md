# Own game reader: feasibility study

Research only, no product code. Written 2026-11-13 (Opus gathered and checked, Fable 5.2 judged).
Question: can HSBG Mac Overlay read Battlegrounds opponent names (and so MMR and the lobby line) without HSTracker's HearthMirror, which refuses every app but HSTracker since 3.7.4?

Rules kept during the study: no reading of Hearthstone's memory, nothing of HearthMirror or HSTracker decompiled, disassembled or patched. Public sources plus static file metadata only (`codesign`, `plutil`, `lipo`, `nm` exported symbols on Blizzard's Mono library, log grep).

## Verdict

- **BUILD our own read-only memory reader after Dec 15, behind a 2-day spike. Do not build OCR.** Confidence 70%.
- **Effort:** 5 to 9 focused days for v1 (names only, arm64 first), hard cap 8 days including the spike. Upkeep about 3 to 6 days a year.
- **Risk:** ban low, legal low, Apple side low now and medium over the years.
- It earns 0 CHF: the overlay is free. The case for it is that without names the overlay loses lobby MMR and the NEXT OPPONENT card, the features HSTracker doesn't have on Mac.

## 1. What the overlay actually needs

Power.log already gives tiers, triples, trinkets, fights, records and the next opponent's hero (`NEXT_OPPONENT_PLAYER_ID`). MMR already comes from Blizzard's public web leaderboard, looked up by name. So the missing piece is **opponent names**; live tribe counts and our own rating are nice to have.

Checked on today's logs: Power.log names only two players in a BG game, you and Bob (`PlayerName=`, `GameAccountId=`). Opponents exist only as hero entities with `PLAYER_ID`, `PLAYER_LEADERBOARD_PLACE` and `NEXT_OPPONENT_PLAYER_ID`. No log (Power, LoadingScreen, Hearthstone, GameNetLogger) has opponent names or any rating. **Names cannot come from logs.**

## 2. The game and macOS (verified on this Mac)

| Fact | Value | Why it matters |
|---|---|---|
| Hearthstone 37.0.255790 engine | Unity 6000.3.11f1, **Mono** (`libmonobdwgc-2.0.dylib`, not IL2CPP) | Classes and fields can be found by name, as all readers do |
| Architectures | Universal, x86_64 + arm64 (the Mono dylib too) | Runs arm64 natively; x86_64 only if the user ticks "Open using Rosetta" |
| Code signature | Developer ID Blizzard, CodeDirectory `flags=0x0`: **no hardened runtime**, no entitlements | A debugger-entitled app can get its task port |
| Mono exports | `_mono_get_root_domain` and ~1,200 `_mono_*` symbols exported | The reader's entry point is findable without guessing |
| HSTracker 3.7.4 | Hardened runtime, `com.apple.security.cs.debugger` + `allow-jit` | Same mechanism we would use |
| This overlay | Ad-hoc signed with `com.apple.security.cs.debugger`; read names through HearthMirror in its own process until 3.7.4 | **Ad-hoc signing plus the debugger entitlement already got Hearthstone's task port on this Mac** |

Apple's rules (Apple doc for `com.apple.security.cs.debugger`, Apple forums):
- The entitlement marks the app as a debugger that "may attach to other processes or get task ports".
- When a non-root user runs it, macOS asks for an administrator's credentials (the "Developer Tools Access" prompt in our README). The grant lasts a 10-hour session.
- Apple's page also says a debugger "can't get the task ports of processes that don't have the Get task allow entitlement". Hearthstone has no such entitlement, yet HSTracker and our overlay both worked. In practice the block applies to hardened-runtime and SIP-protected targets. That is our reading of it, based on what worked, not Apple's wording.
- `com.apple.system-task-ports` is restricted by Apple and not needed. SIP does not need to be turned off.
- Long-term risk: if Blizzard ever turns on the hardened runtime for Hearthstone, every Mac reader dies, HSTracker's included. HSTracker relies on the same path, so this is unlikely to happen quietly.

## 3. Open-source readers

| Reader | License, language | Mac support | Notes |
|---|---|---|---|
| [Zero-to-Heroes/unity-spy-.net4.5](https://github.com/Zero-to-Heroes/unity-spy-.net4.5) (Firestone's "MindVision") | MIT, C# .NET 4.5 | Windows only: Mono offsets for PE 2022.3.62 x86/x64 and **6000.3 x64** | Active (pushed 2026-11-10). Hearthstone layer with all BG paths |
| [hackf5/unityspy](https://github.com/hackf5/unityspy) | MIT, C# | **Yes**: `macos.c` (`task_for_pid` + `vm_read`), ProcessFacadeMacOS, one Mach-O x64 offsets table (Unity 2019.4/2020.3) | Dormant since 2025-02. Calls itself an open rewrite of the closed HearthMirror |
| Firestone app | Overwolf | No Mac build | |

Field paths Firestone reads (BattlegroundsInfoReader.cs):
- **Names, no hover needed:** `GameState.s_instance.m_playerInfoMap` (same source as the game's own `TB_BaconShop.GetBestNameForPlayer`). Fallbacks: `GameMgr` service `m_lastDisplayedPlayerNames`, then the tile text `m_overlay.m_heroActor.m_playerNameText.m_Text`.
- **Leaderboard:** `PlayerLeaderboardManager.s_instance` tiles, `m_entity.m_tags` (tag 30 = PLAYER_ID), `m_realTimeHealth / Armor / PlayerLeaderboardPlace / PlayerTechLevel`, `m_combatHistory`, `m_recentCombatsPanel.m_triplesCount`, `m_raceCounts` (live tribes).
- **Own rating:** `NetCache` service, `m_netCache` entry `NetCacheBaconRatingInfo`, fields `<Rating>k__BackingField` and `<DuosRating>k__BackingField`. Post-game: `GameState.s_instance.m_gameEntity ... <RatingChangeData>k__BackingField._NewRating`.

**Key check (new):** in hackf5's code, the Unity 2019.4 **PE x64 and Mach-O x64 Mono offset tables are identical (23 of 23 fields)**. So Firestone's live-validated 6000.3 PE x64 table is a strong first candidate for Mac x64 and arm64, which are both 64-bit with 8-byte pointers. This is the study's biggest unknown, and it looks smaller than feared. It still has to be validated against the running game in the spike.

Unity's Mono fork is public ([Unity-Technologies/mono](https://github.com/Unity-Technologies/mono), `unity-main` pushed 2026-11-04, mixed MIT/LGPL). Use it only to check numeric struct offsets, never copy its code.

## 4. Upkeep, from Firestone's commit history

The reader walks Mono metadata by name, so ordinary card and balance patches change nothing. BG-relevant breakages in the last ~100 commits:
- 2024-04 "updates for 29.2", 2024-05 "update for 29.4", 2024-05 "fix player name in BG"
- 2026-06 Unity 2022.3.62 64-bit support plus two 64-bit read fixes (one for the BG leaderboard player id)
- 2026-07/08 Unity 6000.3 prep and update
- 2026-08 "have player names populated without mouseover"
- 2026-10 "fix local battle tag read returning only #"

That is roughly 2 to 4 events a year. A field rename costs 1 to 2 hours, because Firestone's fix commit names the new field. A Unity upgrade costs 1 to 3 days, because nobody publishes Mac offsets and we would derive or validate them ourselves. Every patch costs a 10-minute smoke test.

## 5. HSTracker going closed (timeline)

- Always: HearthMirror itself was closed (old HSTracker issue #1114: "repository is private").
- ~2026-10-07: HSTracker issue #1456, "3.6.13 source build blocked: pinned HearthMirror SDK and dSYM URLs return 404" (seen in search results; the issue is gone now).
- **2026-10-27:** `HearthSim/HSTracker` was replaced by a new repository (new id, created 2026-10-27 17:47 UTC). It holds one commit "feat: add docs", a README only, no license and no releases. The old MIT history, issues and releases are no longer on GitHub. Downloads go through hsdecktracker.net.
- 2026-11-12: HSTracker 3.7.4 auto-update. Its HearthMirror refuses other host apps ("licensed for use by HSTracker only. Circumventing or patching this check is not permitted"). We respect that (commit dc454c4).
- The Windows tracker (HDT) is still public, but with no license, "All Rights Reserved".
- **No public explanation from HearthSim found** (GitHub, web, Twitter/Discord mentions). Unverified guesses: forks and companions reusing HearthMirror (e.g. "HSTracker-Companion"), and the commercial owner of HSReplay (Untapped.gg).

A reader of our own, written from MIT sources, never loads, links, patches or decompiles HearthMirror, so the "HSTracker only" notice does not apply to it. Don't copy HearthMirror's API names either.

## 6. Blizzard's stance

- The Blizzard EULA and anti-cheat terms forbid "unauthorized" third-party programs that "intercept, mine or otherwise collect information" from the games. Blizzard may allow tools at its discretion. On paper, memory reading breaks the terms.
- In practice, HDT, HSTracker and Firestone have read memory for 8+ years with a very large user base. Blizzard's tournament handbook (v2.6, §5.10, per HearthSim's help article) allowed deck trackers. Known bans hit game-changing exploits (e.g. Duels deckbuilding via third-party software, patch 28.4), not read-only trackers. No ban of a read-only tracker user found.
- The "anything you can do with pen and paper" rule is quoted widely by the community. We did not find it as official Blizzard text.
- **Ban risk: low** (read-only, shows only what the game shows, no injection, no input). It is not zero, so the README keeps its "use at your own risk" note. The risk is no higher than what the overlay already did through HearthMirror.
- **Legal risk: low.** Both reader sources are MIT: keep their copyright and license text in a NOTICE file. The overlay stays free (HearthSim's terms forbid commercial use of their data anyway).

## 7. Options that avoid memory

| Option | Result |
|---|---|
| Logs | No opponent names, no ratings. Dead end |
| Blizzard public API | Cards, decks, metadata only. No lobby or player API. The leaderboard is web-only (already used) |
| HSReplay / Firestone services | Their data comes from their own memory readers; no public lobby API |
| **Screen OCR** (ScreenCaptureKit + Apple Vision, free, on-device) | Judged seriously, rejected. See below |

Why OCR loses:
- In-game names appear on the leaderboard mainly on **hover** (Firestone needed a 2026-08 change to get names "without mouseover"). Auto-hovering would be input automation, which Blizzard does ban. So the user would have to hover over 7 portraits every game.
- BattleTags are any Unicode (CJK, Cyrillic, accents) in a stylised font. One wrong character means a leaderboard miss. Fuzzy matching only helps for the ~8.7k players on the public leaderboard.
- It needs the Screen Recording permission. With ad-hoc signing, macOS likely asks again after every update (not verified).
- No open-source BG name OCR exists to start from.
- About the same effort as the reader for a worse feature. A hybrid doubles the upkeep.

Still unchecked: whether names show without hover (at game start, or on the opponent's hero during combat). If they do, OCR gets better, but the reader still wins.

## 8. Spike plan (2 days max, after Dec 15)

Nothing touches Hearthstone's memory before Dylan says go.

1. **Look first (15 min, no code).** Play one solo BG game and note where names show without hover. This only decides whether OCR is ever a fallback.
2. **Offsets on paper (3 h, static).** Take Firestone's 6000.3 PE x64 table and check each field against Unity's public Mono source for LP64 Darwin. `_mono_get_root_domain` is already confirmed exported. Pass: a complete candidate table.
3. **Swift CLI (half a day). This is the decisive check.** Get the task port (debugger entitlement, ad-hoc), find `libmonobdwgc-2.0.dylib` in the target's image list, call nothing in the target, read the root domain and list the assemblies. Pass: the list contains `Assembly-CSharp`.
4. **Names (rest of day 2).** Walk to `GameState.s_instance.m_playerInfoMap` and read the 8 names. Pass: correct names on arm64 in 3 games in a row, with no stutter in the game.

**Kill criterion:** if step 3 hasn't passed by the end of day 2, STOP. Ship tiers-only and say so in the README. If step 3 passes and step 4 doesn't, allow at most 2 more days. v1 scope: names only, arm64. Under Rosetta, show "unsupported". Live tribes and our own rating come later.

## 9. What was verified, what was not

Verified today:
- Hearthstone: Mono, Unity version, universal binary, no hardened runtime, the exported Mono symbol.
- HSTracker 3.7.4's entitlements.
- Log contents.
- Both readers: MIT license, macOS code in hackf5, PE-only offsets in Firestone, the Firestone field paths in source, PE x64 = Mach-O x64 offsets in hackf5.
- HSTracker repository recreated on 2026-10-27.
- The wording of Apple's debugger entitlement page.

Not verified:
- That ad-hoc signing plus the debugger entitlement works on other people's Macs. Proven on Dylan's only, though HSTracker uses the same path.
- That `m_playerInfoMap` holds all 8 names on the Mac build (Firestone uses it on Windows).
- That arm64 Mono offsets equal x64.
- The exact current EULA text.
- Screen Recording re-prompts after updates.
- Names on screen without hover.
- Why HearthSim went closed.

Evidence notes with more detail: the session notes file `own-reader-evidence.md` (outside the repo).
