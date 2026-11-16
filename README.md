# Cannonauts

A launch-for-distance party game. Pump the cannon, fire, then bounce, boost and
dive your way down an endless course. Play solo for a personal best, or host a
party of up to eight where everyone flies the same course at the same time and
the furthest flight wins.

Built for phones first (Android, landscape, one or two thumbs) and for desktop
second (Windows, Linux, macOS). Made with Godot 4.7 on top of
[godot-iroh-template](https://github.com/maccam912/godot-iroh-template): peer to
peer over Iroh, four-character party codes, no accounts and no game server.

## Get it

Every commit on `main` is built and published automatically. Grab the newest
build from [Releases](https://github.com/maccam912/cannon/releases/latest):

| Platform | File | Notes |
| --- | --- | --- |
| Android (ARM64, 10+) | `cannonauts-android.apk` | Sideload; development-signed |
| Windows x86_64 | `cannonauts-windows.zip` | Unzip and run |
| Linux x86_64 | `cannonauts-linux.zip` | Unzip and run |
| macOS 13+ (universal) | `cannonauts-macos.zip` | Right-click the app, then Open (not notarized) |

Builds are numbered `0.1.N`, where N is the CI run number; the number is shown
on the title screen.

## How to play

1. **Pump** three times. Tap when the gauge is full; the gold tip is a perfect
   pump. Three perfect pumps earn a pressure bonus.
2. **Fire.** The barrel sweeps; tap to launch at that angle.
3. **Fly.** You have three thrusts and unlimited dives.

| | Touch | Desktop |
| --- | --- | --- |
| Pump / fire | tap anywhere | Space, Enter or click |
| Thrust (limited) | tap the right half | Space, W, Up or left click |
| Dive | tap the left half | S, Down or right click |
| Leave | MENU twice, or Back | Esc |

Thrust kicks you up and forward. Dive brings you down right now without costing
any bounce, so use it to pick your landing spot.

| On the course | What it does |
| --- | --- |
| Spring | Big bounce. Dive onto it for a super bounce. |
| Red barrel | Blasts you up and forward. |
| Hoop | Speed boost when you fly through it. |
| Wingman | Bonks you back up into the air. |
| Jetpack | One more thrust (up to five). |
| Coins | A little speed each, in arcs worth following. |
| Mud | Kills most of your speed. |
| Cactus | Halves your speed. |
| Storm cloud | Swats you toward the ground. |

## Party mode

One player taps **Host a party** and shares the four-character code. Everyone
else taps **Join a party** and types it in. The host picks 1, 3 or 5 rounds and
starts. Each round:

- everyone gets the same course and launches after the same countdown,
- you see the others flying as ghosts, with a live leaderboard,
- the round ends when the last cannonaut stops, and distances add up.

Highest total after the last round wins. Joining mid-round is fine: you watch
that round and play from the next one. If the host leaves, the party ends.

Clients never report a distance. They send what they did (angle, pressure and
when they thrust or dived) and the host replays the flight through the same
deterministic simulation to get the score. How that works, and its limits, is in
[docs/NETWORKING.md](docs/NETWORKING.md).

## Develop

Needs Python 3.11+, Rust via rustup, and your OS compiler toolchain.

```sh
python3 tools/setup.py          # pinned Godot into .tools/, native Iroh library, import
python3 tools/godot.py          # run the game
python3 tools/godot.py --editor # open the editor
python3 tools/check.py          # rules + protocol tests, then a real 3-process match
```

| Path | What lives there |
| --- | --- |
| `game/sim/` | The whole game as plain, deterministic code: course, flight, launch ritual, party rules. No nodes, no network. |
| `game/` | Presentation: world, HUD, menu, lobby, and `main.gd` which runs the flow |
| `network/` | Iroh session and wire protocol, party codes |
| `native/iroh/` | Rust transport (from the template; no game rules) |
| `tests/` | `sim_test`, `party_test`, `protocol`, the multi-process `smoke_peer`, and `render` for screenshots |
| `tools/` | Setup, build, export, version stamping |
| `assets/` | Art, fonts and audio, stored with Git LFS |

The rule of thumb: if it decides an outcome, it belongs in `game/sim/` and gets
a test. `tests/party_test.gd` plays entire matches by calling `tick()`.

Exports, Android setup and the release pipeline are covered in
[docs/BUILDING.md](docs/BUILDING.md); what has actually been tested is in
[docs/VALIDATION.md](docs/VALIDATION.md).

## Credits and licenses

Game code is MIT. Art, fonts and audio are by [Kenney](https://kenney.nl) (CC0).
The Iroh transport derives from Tipragot's MIT Godot-Iroh work via
godot-iroh-template. Details in [THIRD_PARTY.md](THIRD_PARTY.md).
