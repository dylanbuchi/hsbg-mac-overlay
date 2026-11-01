# Leaderboard hover data (tier + most common tribe): where it comes from

Research only, nothing implemented. Written 2026-11-01. Question: can the Mac overlay show each opponent's tavern tier and most common minion type (with count) from turn 1, like the in-game hover and a Windows plugin do?

## Short answer

- **Tavern tier: yes, already available from turn 1** through Power.log (`PLAYER_TECH_LEVEL` on hero entities, we already parse it).
- **Most common tribe and its count: not in Power.log, and not in any public HearthMirror call.** It lives only in the game's memory (a client-side map filled by a real-time server message). Reading it on macOS means our own memory reader of the game's Mono heap: possible in principle, heavy and fragile. Not recommended as a first step.

## 1. Power.log (checked on a real log, /Applications/Hearthstone/Logs/Hearthstone_2026_11_01_00_29_27/Power.log, 1 GB)

- Tags present: `PLAYER_TECH_LEVEL` (804 changes, set on the hero/player entities from turn 1), `PLAYER_LEADERBOARD_PLACE`, `CARDRACE` (4344, on minion entities), many `BACON_*` tags.
- The `BACON_SUBSET_*` tags (DRAGON, BEAST, MURLOC...) mark which tribes are in the game's minion pool for the lobby (5 of them). They are not per-player counts.
- No tag or line mentions a per-player tribe counter (0 hits for `RealTimeBattlefieldRaces` / `raceCounts`). The Windows plugin's author reached the same conclusion on a full log.
- Opponent boards are not logged during the shop phase (their minions only appear as entities during combat), which is why `lastSeenTribes` is empty until we have fought that player.

## 2. HearthMirror (the library in /Applications/HSTracker.app, read-only `strings`/`nm`)

- Public Battlegrounds calls: `getBattlegroundsLobbyInfo` (names, hero card id, account id; we use it), `getBattlegroundsLeaderboardHoveredEntityId` (which portrait the mouse is on, no data), `getBattlegroundsMinionPool`, `getAvailableBattlegroundsRaces` / `getUnavailableBattlegroundsRaces` (which tribes are in this lobby), `getBattlegroundsTeammateBoardState` (duos), `getBattlegroundsRatingInfo/Change`.
- None returns per-player tier, tribe or counts for the leaderboard. There is no `raceCounts`, `m_overlay` or `PlayerLeaderboardCard` string in the binary (only the class name `PlayerLeaderboardManager`, used for something else).
- Internally the Mac framework has a Mono reader (`mono_get_root_domain`, MonoImage, page reads), but it is private: the ObjC surface has fixed getters only, no generic "walk this field path" call.
- Useful small win: `getAvailableBattlegroundsRaces` tells which 5 tribes exist in the lobby, so a guess among them is narrower (no per-player info though).

## 3. Windows side: Tantrum's Battlegrounds Toolkit (github.com/RTantrumR/HDT-Plugin-Cards, Apache-2.0)

Apache-2.0 is compatible with MIT for **learning the technique**; we copy no code or assets (copying would need a NOTICE and attribution).
- Tier comes from the log: `PLAYER_TECH_LEVEL` on HDT's hero entities (accepted if 1 to 7, latched because it can read 0 while the game swaps hero entities), place from `PLAYER_LEADERBOARD_PLACE`.
- Tribe and count come from **game memory only**, because the server sends them as a real-time message (`PlayerRealTimeBattlefieldRaces`) that never reaches the log. The plugin reflects into HearthMirror's private connection and walks the heap path `PlayerLeaderboardManager.s_instance.m_teams[].m_playerLeaderboardCards[]`, then per card the hero entity tags (ENTITY_ID tag 53 as key) and `m_overlay.m_raceCounts` (a map race id to count). It polls about every 2 s, live from turn 1.
- Display rule it reproduces from the client: race ALL (id 26) counts toward every tribe; the top total is shown; a tie shows the type without a count.
- HDT main repo only exposes the hovered entity id; no tribe-count feature in HDT or HSTracker. That is why a plugin had to reach into memory by itself.

## 4. Verdict and minimal design

Feasible on macOS: tier yes (done), tribe count only via our own Mono heap read (hard).

- **Cheap option now (recommended):** show tier from turn 1 on every portrait (check it is displayed before the first fight), and keep tribes from the last fight with their age. Optionally show the lobby's 5 available tribes in the legend so Dylan knows the candidates.
- **Memory option (only if Dylan wants parity):** read the path above from the Hearthstone process with our own reader (task_for_pid, which our debugger entitlement already allows for HearthMirror), resolving Mono class layouts at runtime. Risks: the field names and layout change with game patches (breaks silently after an update), Apple Silicon Mono internals differ from the Windows reflection layer the plugin rides on, large effort (weeks), and it must be strictly read-only. Needs a kill switch and fallback to the log-based data.
- Ask HearthSim (HSTracker/HearthMirror maintainers) whether they would add a public getter; that would be the clean route.

Not verified: any real memory read on the Mac, the HearthMirror source (not public), the exact current client class names (taken from the plugin's code as of its v0.7.0).
