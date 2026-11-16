# Networking

## Shape of a party

Cannonauts is a launch game, so players do not interact mid-flight. That makes
the multiplayer model simple and cheap:

- **Same course, same moment.** The host picks a seed per round. Every device
  generates the identical course from it and launches after the same countdown.
- **Fly locally.** Each device simulates its own cannonaut at 60 Hz with no
  network in the loop, so controls feel the same on a bad connection.
- **Replay to score.** When a flight ends, the client sends what it did: launch
  angle, pressure, and the ticks at which it thrust or dived. The host replays
  that through the same simulation and records its own answer.
- **One power level.** Solo upgrades stay out of it. The host picks a preset
  (Stock, Boosted or Maxed) that every flight and every replay uses, so the
  host never has to trust a client's claimed upgrade levels.
- **Ghosts are cosmetic.** Positions are relayed ten times a second so you can
  watch the others. They never affect a score.

The host is one of the players. There is no dedicated server and no host
migration: if the host leaves, the party ends.

## Layers

| Layer | File | Job |
| --- | --- | --- |
| Rules | `game/sim/party.gd` | Phases, rounds, verification, standings. No I/O. |
| Protocol | `network/session.gd` | Messages, validation, the mirrored view |
| Codes | `network/rooms.gd`, `rendezvous.gd` | Four-character code create/resolve/revoke |
| Transport | `native/iroh/` | Iroh QUIC streams and datagrams (Rust) |

`Session` exposes the same view on every device (`phase`, `round_number`,
`rounds`, `round_seed`, `roster`, `ghosts`), so screens do not care about role.
Only the host owns a `Party`.

The code service is discovery only: it maps a short code to the host's Iroh
endpoint ID. Game traffic goes over Iroh, directly when possible and through
N0's relays otherwise. No port forwarding is needed.

## Why replays agree

`game/sim/flight.gd` is written to produce bit-identical results everywhere:

- fixed 60 Hz ticks, never frame time;
- 64-bit scalar floats with `+ - * /` and `sqrt` only (all exactly rounded by
  IEEE 754), no `Vector2` (32-bit) and no libm `sin`/`cos` (the launch angle
  uses a Taylor series built from basic arithmetic);
- an integer xorshift generator with explicit 32-bit masks for the course.

`tests/sim_test.gd` checks golden distances recorded on Apple Silicon; CI
replays them on x86 Linux and Windows. `tests/smoke_peer.gd` has separate
processes compare the host's verified distance with their own.

## Wire protocol

The application ALPN is `cannonauts/1` (`native/iroh/src/lib.rs`) and the code
namespace is `cannonauts/1` (`project.godot`). The message protocol is version 2;
a client on another version is turned away at `hello`. Messages are UTF-8 JSON,
at most 1024 bytes, parsed as plain data.

| Channel | Delivery | Client to host | Host to clients |
| --- | --- | --- | --- |
| 0 | Reliable, ordered | `hello`, `inputs`, `result` | `welcome`, `phase`, `roster` |
| 1 | Unreliable, ordered | `pos` | `ghosts` |

| Message | Fields |
| --- | --- |
| `hello` | `version`, `name` |
| `welcome` | `version` |
| `phase` | `ph` phase, `r` round, `n` rounds, `u` power level, `seed`, `t` ticks left |
| `roster` | `p`: rows of `[id, name, slot, total_cm, round_cm, best_cm, playing]` |
| `inputs` | `r` round, `k` piece index, `i` up to 800 characters of input log |
| `result` | `r` round, `a` angle in tenths of a degree, `p` pressure per mille, `n` number of input pieces sent |
| `pos` | `r`, `x`, `y`, `s` state (0 aiming, 1 flying, 2 landed) |
| `ghosts` | `r`, `g`: rows of `[id, x, y, state]` |

The input log is a string of `<letter><ticks since the previous input>` with
`t` for thrust and `d` for dive, so `t12d40` means thrust at tick 12 and dive at
tick 52. It is capped at 1500 inputs and 7200 characters. A long upgraded flight
does not fit one packet, so the log travels as ordered `inputs` pieces (at most
nine) and the `result` that follows says how many there were.

Phases: `LOBBY`, `COUNTDOWN` (3 s), `PLAYING`, `RESULTS`, `FINAL`. Clients must
fire within 15 seconds of the round starting or the cannon fires for them. A
flight is capped at five minutes and a round a little beyond that; anyone who
has not reported by then scores zero.

## What the host checks

- `hello` only from a peer that just connected, with the right version, while
  there is a seat. Unintroduced peers are dropped after five seconds.
- `inputs` pieces only for the current round, in order, each at most 800
  characters and at most nine of them; anything else discards what was received.
- `result` only during `PLAYING`, for the current round, from a seated player
  who still owes one, with whole-number angle and pressure inside their legal
  ranges, a piece count that matches, and a well-formed input log. One result
  per player per round.
- The distance is never read from the client. Inputs that could not have taken
  effect (a fourth thrust, a dive on the ground) simply do nothing in the replay.
- `pos` values are bounded and never scored.
- Names are trimmed to twelve printable characters.

Clients accept `phase`, `roster` and `ghosts` only from the host, and discard
anything malformed or out of range.

Verification is spread over frames (1500 flight ticks per host tick) so a phone
hosting eight players does not stall.

## Limits worth knowing

- **Pressure and angle are trusted within range.** The pump timing happens on
  the client, so a modified client could always claim a perfect launch. The
  flight after that is fully verified. Good enough among friends; not a ranked
  ladder.
- **The host is trusted.** It runs the rules and could cheat.
- **A code is not a password.** Anyone with a valid code can try to join.
- **Mobile background.** Backgrounding the app closes the session and revokes
  the code; rejoin or rehost on return.
- **No reconnect.** A dropped client rejoins as a new player and plays from the
  next round.

## Short-code service

Configured in `project.godot`:

```ini
[network]
iroh/rendezvous_url="https://iroh-rendezvous.maccam912.workers.dev"
iroh/session_id="cannonauts/1"
```

- `POST /v1/join-codes` with `endpoint_id`, `session_id`, `expires_in: 600`
  returns `code`, `expires_at` and a `revoke_token`.
- `GET /v1/join-codes/{code}` resolves it, or 404.
- `DELETE /v1/join-codes/{code}` with the bearer token revokes it.

Codes last ten minutes. While the lobby is open the host renews automatically
(new code first, then the old one is revoked), and existing connections outlive
their code. If the service is down, **Copy ticket** in the lobby gives a full
Iroh ticket that the join box also accepts.
