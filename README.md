# Godot Iroh Starter

A generic multiplayer game starter: Godot 4.7.2, a Rust Iroh 1.4.1 GDExtension,
four-character room codes, and GitHub Actions builds for Android and desktop.
Replace the small arena demo with your game. There are no racing systems or assets.

![Starter demo](docs/preview.png)

## Start developing

Install **Python 3.11+**, [Rust via rustup](https://rustup.rs/), and your OS compiler:
Xcode Command Line Tools on macOS, Visual Studio Build Tools with Desktop C++ on
Windows, or `build-essential pkg-config` on Ubuntu. Then, from this folder:

```sh
python3 tools/setup.py
python3 tools/godot.py --editor
```

Use `python` instead of `python3` on Windows if that is your installed command.
Press F6/F5 to run the demo, or `python3 tools/godot.py` to run it directly.
Setup downloads the pinned engine into `.tools/`, builds the native extension,
and imports the project. Rust is only needed when building/changing the native
library. Without it, the project still opens as an offline playground.

The helper uses a self-contained Godot installation; it does not replace your
system Godot, templates, or editor settings. First setup compiles Rust dependencies
and can take several minutes. The engine API bindings target Godot 4.5 for ABI
compatibility; the actual editor and export templates are **4.7.2**.

## Play with another instance or device

1. Run two copies. Click **Host game** on one.
2. Give the other player the four-character code. Enter it and click **Join game**.
3. Move with WASD/arrows, or tap/click the arena. Send a message to the room.
4. Use **Leave** to disconnect. **New code** replaces an expiring code without
   ending the game. Codes last ten minutes; existing connections outlive them.

The configured code service is the same owner-managed rendezvous service used by
the existing games. It is configured in `project.godot`, not hidden in a binary.
**Copy host ticket** provides a fallback that bypasses that HTTP service. Tickets
include the public endpoint ID and currently known routes; ask for a fresh one
after network changes. Internet discovery and relay access may still be needed.

## What's included

- Host-authoritative movement for a host and up to seven clients, room chat,
  join/leave handling, input validation, and bounded packet queues.
- Iroh direct connections with relay fallback, reliable messages and ordered
  unreliable snapshots, timeouts, and Android DNS/JNI initialization.
- Four-character code creation, resolution, renewal, expiry, and revocation;
  stale HTTP replies cannot reopen a closed room.
- A source-only starting point, a pinned toolchain, export presets, real
  multi-process tests, tagged GitHub releases, and downloadable CI artifacts.

| Target | Output | Notes |
| --- | --- | --- |
| Android ARM64 | Development-signed APK | Android 10+, touch controls, JNI bridge |
| Windows x86_64 | ZIP with EXE and native DLL | Built/tested on a Windows runner |
| Linux x86_64 | ZIP with executable and native SO | Built/tested on Ubuntu |
| macOS ARM64 + Intel | Universal app ZIP | macOS 13+, ad hoc signed locally |
| Linux dedicated server | Headless executable ZIP | Same authoritative session |

iOS and Web are outside the supported build matrix. Native Iroh cannot simply
be exported into a browser. Neither App Store/Play Store publishing nor console
SDK integration is included.

## Check and build

```sh
python3 tools/check.py                  # Protocol tests + host/two-client session
python3 tools/check.py --relay-only     # Also requires public Iroh relays
python3 tools/check.py --codes --relay-only  # Live code service + revocation
python3 tools/export.py macos          # Or linux/windows on those operating systems
```

Android setup and all export commands: [docs/BUILDING.md](docs/BUILDING.md).
Outputs land in `build/artifacts/` with SHA-256 checksums.

## Make it your game

Start with [docs/CUSTOMIZING.md](docs/CUSTOMIZING.md). The important boundaries are:

| File | Responsibility |
| --- | --- |
| `demo/` | Disposable arena, controls, and UI |
| `network/session.gd` | Demo game state and authoritative protocol |
| `network/rooms.gd` | Room-code lifecycle and asynchronous cancellation |
| `network/rendezvous.gd` | Short-code HTTP API |
| `native/iroh/src/` | Transport only; no game rules |
| `tools/` | Pinned setup, builds, exports, checks |

The example uses explicit packets through `MultiplayerPeer`, **not Godot's
high-level RPC/MultiplayerSpawner API**. This keeps authority and message validation
visible. See [docs/NETWORKING.md](docs/NETWORKING.md) before changing the protocol.

## Put the template on GitHub

This folder is local; creating it does not publish a repository or run remote CI.
Create an empty GitHub repository, initialize/commit this folder, add its remote,
and push. In repository Settings → General, enable **Template repository** to get
GitHub's **Use this template** button for future games.

Every push/PR builds all supported platforms. Tags beginning with `v` publish a
release only after every build succeeds. The Android key is a development key;
store signing remains a separate setup. Read [docs/BUILDING.md](docs/BUILDING.md)
for Actions, release, and signing details, and [docs/VALIDATION.md](docs/VALIDATION.md)
for what has actually been exercised locally.

## Versions and licenses

As checked on November 3, 2026, [Godot 4.7.2 is the latest stable release;
4.8 is beta](https://godotengine.org/download/archive/).
[Iroh 1.4.1](https://docs.rs/iroh/1.4.1/iroh/) is pinned in Cargo.toml/Cargo.lock.
Version and checksum pins live in `tools/versions.json` and `rust-toolchain.toml`.

Template code is MIT. The transport derives from Tipragot's MIT Godot-Iroh work
via the user's racinggame integration; see [THIRD_PARTY.md](THIRD_PARTY.md).
