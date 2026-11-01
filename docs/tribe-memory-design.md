# Per-player tribe counts from game memory: feasibility spike and design (provisional)

Written 2026-11-01. **Status: proven live by Dylan** (6 runs in one real game: counts grow between rounds, row order changes so match by entity id, one entity id was replaced mid-game, race ALL appears). Now integrated in the app: `Sources/TribeMemory` (ObjC++ reader), `LiveTribes.swift` (mapping, gate), `OverlayModel` (poll ~3 s) and the Settings toggle. The text below was written before the integration.

## Verdict

Not killed. It is much cheaper than the earlier notes feared: no own Mono reader is needed. HearthMirror (inside HSTracker.app, arm64 slice) already exports a generic Mono path reader as plain C++ symbols.

## Exact access path (what the spike does)

1. Same entry as `HearthMirrorBridge`: `dlopen` the framework, `[[HearthMirror alloc] initWithPID:withBlocking:NO]` (task_for_pid, read-only `vm_read`; the app does this today).
2. Get the `MonoImage*`: ObjC ivar `_mirror` (a `hearthmirror::Mirror*`), then `*(void**)mirror` is an impl struct whose `+8` is the `MonoImage*` (null until the game has loaded; read from `Mirror::isInMainMenuInternal` and `getBattlegroundsLobbyInfoInternal` disassembly, which both do exactly this).
3. Exported C++ symbols (found with `nm`, mangled names in `spike/tribe_spike.mm`):
   - `hearthmirror::getObject(std::vector<std::string> const&, MonoImage*)`: class name, then static field, then instance fields. `{"PlayerLeaderboardManager","s_instance","m_teams"}` is the same shape HearthMirror's own lobby code uses (`"GameState","s_instance"`).
   - `MonoValue::operator[](char const*)`, `intValue(MonoValue&)`, `IsMonoValueEmpty`.
   - `MonoValue` is 0x60 bytes, type tag at +0; an array keeps its element pointer at +0x48 and count at +0x58 (the non-exported `operator[](int)` is just `ptr + i*0x60`). This is an ABI guess from disassembly and the main risk.
4. Walk (same as the Windows plugin, `LeaderboardRaceScry.cs`, learned from, nothing copied): `m_teams` (List: `_items`, `_size`) → each team `m_playerLeaderboardCards` (List) → card `m_playerHeroEntity.m_tags.m_values` (Dictionary: `_entries[i].key/value`, key 53 = ENTITY_ID) and `card.m_overlay.m_raceCounts` (Blizzard `Map<TAG_RACE,int>`: `touchedSlots`, `linkSlots[i].HashCode`, `valueSlots[i]`; slot used when HashCode top bit is set, the race id is the low 31 bits; the keys may come back as enum structs so the hash is used).

Static evidence: all class/field names (`PlayerLeaderboardManager`, `s_instance`, `m_teams`, `m_playerLeaderboardCards`, `m_playerHeroEntity`, `m_overlay`, `m_raceCounts`) are present in the installed `Assembly-CSharp.dll` metadata (client build of 2026-10-26, read-only `strings`). Mac HearthMirror already reads `valueSlots` of a Blizzard Map (`m_playerInfoMap`) and List `_items/_size`, so its Mono reader handles these containers.

Not verified: that a live read returns data, that the hero entity id matches the log's entity ids (plugin says yes), hero card id and player name (string extraction from `MonoValue` not implemented; the entity id already joins to the Power.log hero entity), Rosetta/x86_64 irrelevant (arm64 only).

## Fragility

- Game patch: renamed fields/classes (`m_raceCounts`, `m_overlay`) break silently. Mitigation: every step returns empty on failure, treated as "no data".
- HSTracker update: mangled symbols and the `MonoValue` layout (0x60, +0x48/+0x58) can change; the impl offset `+8` too. Mitigation: resolve symbols with `dlsym` and fall back to log data when any is missing; keep a layout self-check (e.g. read a known int through `getObject` + `intValue` and compare with `getBattlegroundsLobbyInfo`).
- This leans on private C++ internals of another project; clean fix is asking HearthSim for a public getter (draft below).

## Minimal integration design (do NOT build yet)

- Poll about every 2 s, only while a Battlegrounds game is in progress (the lobby snapshot already says so); one pass per poll, no loops inside a pass.
- Settings kill switch "Live tribe counts (reads game memory)", off by default for the first release; also auto-off after N consecutive failures.
- Fallback: current log-based `lastSeenTribes`. UI: a "live" marker on counts from memory vs "last seen in combat" on log data; show the tie rule as the game does (top total; tie shows the type without a count; race ALL counts for every tribe).
- Read-only guarantee in code and docs: no writes, no suspend, no injection; only fields the game displays in its own hover.
- Reader behind a protocol (`LeaderboardTribeSource`), real implementation in an ObjC++ target, join to players by hero entity id.

## Tests with fakes

Decode the Map/List/Dictionary walk against a fake `MonoValue` tree; the race-count → display rule (ALL, tie, empty); join by entity id; failure paths (symbol missing, image null, empty map) return nil and fall back to log data; poll gating and the kill switch.

## Draft issue for HearthSim (cleaner alternative)

"Could HearthMirror expose a public getter for the Battlegrounds leaderboard tile data (per hero entity id: map of race → count from `PlayerLeaderboardManager`...`m_overlay.m_raceCounts`)? It is displayed in the game's own hover but never reaches Power.log. Read-only, same pattern as `getBattlegroundsLobbyInfo`."

## To finish the proof

Run once during a Battlegrounds game (shop phase, after the lobby is loaded), then paste the output:

    spike/build.sh && spike/build/tribe_spike
