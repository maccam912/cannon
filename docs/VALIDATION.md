# Validation record

Checked locally on November 3, 2026. This is a local template repository with no
GitHub remote configured; GitHub Actions has not run for it yet.

| Check | Result / boundary |
| --- | --- |
| Version selection | Official archive: Godot 4.7.2 stable; 4.8 beta2. Iroh 1.4.1 |
| Rust build | macOS ARM64 + Intel universal library; Android ARM64 library |
| Rust formatting and lint | `cargo fmt --check` and locked `cargo clippy -- -D warnings` passed |
| Godot import/protocol | Pinned 4.7.2 import, input validation, snapshot authority, reset checks passed |
| Desktop multiplayer | One host + two clients: join, movement, reliable chat, snapshots, disconnect cleanup passed |
| Relay-only multiplayer | Same multi-process test with direct IP transport disabled passed |
| Live short codes | Create, resolve, connect via relays, and revoke-on-leave passed |
| macOS export | Universal app ZIP; plist lint, strict deep all-architecture signature verification, exported native-host smoke passed |
| Android package | Debug APK, native library and Java bridge present, APK signature verified |
| Android runtime | Installed APK on ARM64 Android 35 emulator hosted two macOS clients using the live code service; both clients required relays and passed movement/chat/snapshot checks |
| Android background | Sending app to Home closed the session; resolving the former code returned HTTP 404 |
| Visual check | Desktop render and Android emulator screen inspected; room controls, player markers, and chat fit |
| Workflow syntax | `actionlint` passed for both workflows |
| Python | All tool modules compiled successfully |

The emulator was opened read-only and shut down after the test. No physical phone,
cellular transition, long session, packet impairment, or public matchmaking load
test was performed. Intel macOS was compiled and signed but not executed on Intel
hardware. Windows, Linux, and dedicated-server artifacts need their native CI
jobs; their success is not inferred from the Mac or Android builds. Code renewal,
malicious-peer resistance, reconnect, and cross-version upgrade behavior need
additional game-specific acceptance tests.

## Local outputs

Generated and ignored by Git:

- `build/artifacts/godot-iroh-starter-android.apk` and `.sha256`
- `build/artifacts/godot-iroh-starter-macos.zip` and `.sha256`
- `build/final-check.log`, `build/smoke/*.log`, `build/smoke-relay/*.log`,
  `build/smoke-codes/*.log`
- `build/android-export.log`, `build/macos-export.log`
- `build/android-smoke/client-0.log`, `client-1.log`, and emulator screenshots
- `build/android-code-after-background.json` (404 response body)
- `build/android-runtime.log`

These files are not present in a source-only clone. Run `tools/check.py`, the
optional `--relay-only` / `--codes` checks, and `tools/export.py` to regenerate
the relevant evidence. The checked-in `docs/preview.png` shows the actual demo.

## Repeat the Android cross-play test

1. Export/install the APK as described in BUILDING.md and open it from the launcher.
2. Tap **Host game**, then write the displayed code into a temporary text file.
3. In two desktop terminals run:

   ```sh
   python3 tools/godot.py --headless --script res://tests/smoke_peer.gd -- client /absolute/path/code.txt --codes --relay-only
   ```

4. Both should print `CLIENT_PASS` and exit. This verifies each saw the host and
   the other client, received authoritative movement and snapshots, and got room chat.
5. Background the Android app; the old code should stop resolving. Delete the
   temporary text file. Use a fresh code for another run.

Godot 4.7.2 uses `com.godot.game.GodotAppLauncher` as its exported Android activity
alias. `command_line_params` sent to that launcher were ignored in this test, so
the Android host was started through the visible **Host game** button. Do not
assume old Godot intent-based automation still controls the game.
