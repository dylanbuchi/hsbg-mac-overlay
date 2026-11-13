# Third-party notices

## HSTracker

Portions of `Sources/HSBGMacOverlay/LeaderboardLayout.swift` (the Battlegrounds
leaderboard slot geometry) are derived from HSTracker's
`BattlegroundsOpponentDeadForView.swift` / `BattlegroundsLeaderboardLayout`
(https://github.com/HearthSim/HSTracker, version 3.7.1), licensed under the MIT License:

```
Copyright (c) HearthSim
Copyright (c) 2015-2017 Benjamin Michotte

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

## unity-spy (Firestone) and unityspy

The built-in game reader in `Sources/GameMemory` (Swift, written for this project) follows the
approach of these readers: walking Mono's domain, assemblies, class cache, fields and static data
by name. Its Hearthstone field paths (`GameState.s_instance.m_playerInfoMap`, `SharedPlayerInfo.m_name`,
the `GameMgr` service's `m_lastDisplayedPlayerNames`, the service locator path) and its starting
Mono offsets (`Unity6000_3_x64_PE_Offsets`) come from them. The macOS values that differ were
measured on the running game.

- unity-spy-.net4.5, https://github.com/Zero-to-Heroes/unity-spy-.net4.5, MIT License
- unityspy, https://github.com/hackf5/unityspy, MIT License:

```
The MIT License (MIT)

Copyright (c) 2019 brian t

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## App icon

The app icon (`packaging/AppIcon.icns`) is original artwork (`packaging/AppIcon-master.png`, 1024 px), covered by this repository's MIT license. It uses no Blizzard or HearthSim assets. To regenerate it: `scripts/make-icon.sh`.

## HS BG Cards (hsbg.cards)

The NEXT OPPONENT card shows tavern tier badges and minion art from
[HS BG Cards](https://hsbg.cards). They are downloaded at runtime, only when needed,
and cached on disk in `~/Library/Application Support/HSBGMacOverlay/` (`tier-images/`
and `card-art/`). They are not in this repository or in the app package.
Card data and images courtesy of HS BG Cards; not affiliated with Blizzard.

## Not included

This repository and the app package contain no HSTracker binaries, no HearthMirror
framework and no Blizzard artwork. The app never loads HearthMirror. At runtime it only
displays, from the user's own HSTracker installation (after checking it is HearthSim's signed
build where noted in the README), the tavern tier shields and the round tribe pictures. These
are never copied, extracted, saved or bundled.

The tier badges and minion art from hsbg.cards are Blizzard artwork. They are cached
on the user's disk as described above and never shipped with the app.

Hearthstone and its artwork are © Blizzard Entertainment. This project is not
affiliated with Blizzard Entertainment, HearthSim or HS BG Cards.
