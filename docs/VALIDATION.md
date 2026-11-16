# Validation record

What has actually been exercised, and what has not. Checked on November 16,
2026 on an Apple Silicon Mac unless a row says otherwise.

| Check | Result |
| --- | --- |
| Flight, course and launch rules (`tests/sim_test.gd`) | Pass. Includes: dive adds no energy and dive-spam gains nothing, three thrusts only, every item's effect, input log round trip, live flight equals replay for 20 random flights, 120 bot flights all terminate |
| Party rules (`tests/party_test.gd`) | Pass. Full three-round match, host-only controls, 14 kinds of bad submission rejected, timeouts, leavers, late joiners, eight-seat cap |
| Wire protocol (`tests/protocol.gd`) | Pass. Host ignores strangers, stale rounds and malformed data; clients accept only well-formed host messages |
| Desktop multiplayer (`tests/smoke_peer.gd`) | Pass. One host and two client processes over real Iroh play a round; each client's own distance equals the host's replay |
| Cross-CPU determinism | Golden distances recorded on ARM64 macOS; the Linux x86_64 CI job reproduced them. See the Actions history for Windows and macOS runners |
| Desktop look | `tests/render.gd` screenshots at 1280x720 and 1170x540 inspected: menu, pump, angle, flight, landing, lobby, countdown, party flight with ghosts, round and final tables |
| Android package | Release-mode APK, 36 MB, ARM64 library and Java bridge present, signature verified |
| Android runtime | Installed on a Pixel 7 emulator (Android 15, 2400x1080). Landscape, safe-area inset applied, touch pump/fire/thrust/dive, best score persisted across an APK update |
| Android hosting and cross-play | The emulator hosted a party with a live four-character code; two macOS clients joined by code, played a round and matched the host's verified scores |

## Not tested

- A physical phone, cellular networks, or switching networks mid-game.
- More than three players at once, or a full eight-player room.
- Real thumbs: tuning (launch speeds, item odds, bounce values) was done with
  bots and a few scripted taps, not play sessions. Expect to adjust the
  constants at the top of `game/sim/flight.gd` and the weights in
  `game/sim/course.gd`. Changing either changes the golden values in
  `tests/sim_test.gd`; the test prints the new ones.
- Sound and music by ear. Files load and play calls run; nobody has listened.
- Intel Macs (compiled and signed, not executed).
- Long sessions, packet loss, and code renewal after the ten-minute expiry.
- Relay-only connections for this game (the manual `relay-smoke` workflow
  covers it).

## Repeat the Android cross-play test

1. Export and install the APK (see BUILDING.md) and open the game.
2. Tap **Host a party** and write the code into a text file.
3. In two terminals run:

   ```sh
   python3 tools/godot.py --headless --script res://tests/smoke_peer.gd -- client /absolute/path/code.txt --codes
   ```

4. When both appear in the lobby, choose 1 round and tap **Start**. Play the
   round on the phone (or let the cannon fire itself after 15 seconds).
5. Both terminals should print `CLIENT_PASS`.
