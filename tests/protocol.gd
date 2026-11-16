extends "res://tests/harness.gd"
## Wire-protocol validation on both sides, driven without a real connection.

const Party := preload("res://game/sim/party.gd")

func label() -> String:
	return "PROTOCOL"

func run() -> void:
	var session: Node = root.get_node("Session")
	session.set_physics_process(false)

	# --- Host side: clients only ever express intent.
	session.role = "host"
	session.party = Party.new(5)
	session.party.add_player(1, "Host")
	session.pending[2] = 0
	session.pending[4] = 0
	session._receive(2, {"type": "hello", "version": 1.0, "name": "[Ada]"})
	check(session.party.players.has(2) and session.party.players[2].name == "Ada", "hello seats a cleaned name")
	session._receive(4, {"type": "hello", "version": 99.0, "name": "Old"})
	check(not session.party.players.has(4) and not session.pending.has(4), "wrong protocol version is turned away")
	session._receive(3, {"type": "hello", "version": 1.0, "name": "Ghost"})
	check(not session.party.players.has(3), "hello from a peer that never connected is ignored")
	session._receive(2, {"type": "result", "r": 1.0, "a": 450.0, "p": 500.0, "i": ""})
	check(session.party.players[2].round_cm == -1, "no results in the lobby")
	session.party.start(1)
	while session.party.phase != Party.Phase.PLAYING:
		session.party.tick()
	session._mirror_party()
	session._receive(2, {"type": "pos", "r": 1.0, "x": 1e12, "y": -50.0, "s": 1.0})
	check(session.ghosts[2].x == 1000000.0 and session.ghosts[2].y == 0.0, "ghost positions are clamped")
	session._receive(2, {"type": "pos", "r": 1.0, "x": "far", "y": 1.0, "s": 1.0})
	session._receive(2, {"type": "pos", "r": 1.0, "x": 5.0, "y": 1.0, "s": 7.0})
	session._receive(2, {"type": "pos", "r": 2.0, "x": 5.0, "y": 1.0, "s": 1.0})
	session._receive(9, {"type": "pos", "r": 1.0, "x": 5.0, "y": 1.0, "s": 1.0})
	check(session.ghosts[2].x == 1000000.0 and not session.ghosts.has(9), "malformed, stale and stranger positions are ignored")
	session._receive(9, {"type": "result", "r": 1.0, "a": 450.0, "p": 500.0, "i": ""})
	session._receive(2, {"type": "result", "r": 1.0, "a": 450.0, "p": 99999.0, "i": ""})
	session._receive(2, {"type": "result", "r": 1.0, "a": 450.0, "p": 500.0, "i": {"evil": true}})
	session._receive(2, {"type": "result", "distance": 99999999.0})
	check(session.party._jobs.is_empty(), "bad results never reach the verifier")
	session._receive(2, {"type": "result", "r": 1.0, "a": 450.0, "p": 500.0, "i": "t20"})
	check(session.party._jobs.size() == 1, "a well-formed result is queued for replay")
	session._receive(2, {"type": "phase", "ph": 4.0, "r": 3.0, "n": 3.0, "seed": 1.0, "t": 0.0})
	check(session.party.phase == Party.Phase.PLAYING, "clients cannot change the phase")
	session._peer_disconnected(2)
	check(not session.party.players.has(2) and not session.ghosts.has(2), "leaving frees the seat")

	# --- Client side: only the host's word counts, and only if well formed.
	session.party = null
	session.role = "client"
	session.local_id = 2
	session._welcomed = true
	session.phase = Party.Phase.LOBBY
	session.roster = []
	session.ghosts.clear()
	session._receive(3, {"type": "phase", "ph": 2.0, "r": 1.0, "n": 3.0, "seed": 77.0, "t": 100.0})
	check(session.phase == Party.Phase.LOBBY, "only the host announces phases")
	for bad: Dictionary in [
			{"type": "phase", "ph": 9.0, "r": 1.0, "n": 3.0, "seed": 77.0, "t": 100.0},
			{"type": "phase", "ph": 2.0, "r": 1.0, "n": 4.0, "seed": 77.0, "t": 100.0},
			{"type": "phase", "ph": 2.0, "r": 1.0, "n": 3.0, "seed": "x", "t": 100.0},
			{"type": "phase", "ph": 2.5, "r": 1.0, "n": 3.0, "seed": 77.0, "t": 100.0},
			{"type": "phase", "ph": 2.0, "r": 1.0, "n": 3.0, "seed": 77.0}]:
		session._receive(1, bad)
	check(session.phase == Party.Phase.LOBBY, "malformed phases are ignored")
	session._receive(1, {"type": "phase", "ph": 2.0, "r": 1.0, "n": 3.0, "seed": 77.0, "t": 100.0})
	check(session.phase == Party.Phase.PLAYING and session.round_seed == 77 and session.round_number == 1, "host phase accepted")
	for bad_rows: Variant in [
			"nope", [[1.0, "A", 0.0, 0.0, 0.0, 0.0]], [[1.0, 5.0, 0.0, 0.0, 0.0, 0.0, 1.0]],
			[[1.0, "A", 99.0, 0.0, 0.0, 0.0, 1.0]], [[1.0, "A", 0.0, -5.0, 0.0, 0.0, 1.0]]]:
		session._receive(1, {"type": "roster", "p": bad_rows})
	check(session.roster.is_empty(), "malformed rosters are ignored")
	session._receive(1, {"type": "roster", "p": [[1.0, "Host", 0.0, 500.0, 500.0, 500.0, 1.0], [2.0, "<Me>", 1.0, 900.0, -1.0, 900.0, 1.0]]})
	check(session.roster.size() == 2 and session.entry(2).name == "Me" and session.entry(2).round_cm == -1, "roster accepted and names cleaned")
	check(session.standings()[0].id == 2, "standings sort by total")
	session._receive(1, {"type": "ghosts", "r": 5.0, "g": [[1.0, 10.0, 2.0, 1.0]]})
	session._receive(1, {"type": "ghosts", "r": 1.0, "g": [[1.0, "x", 2.0, 1.0]]})
	check(session.ghosts.is_empty(), "stale or malformed ghosts are ignored")
	session._receive(1, {"type": "ghosts", "r": 1.0, "g": [[1.0, 10.0, 2.0, 1.0]]})
	check(session.ghosts[1].x == 10.0 and session.snapshots_received == 1, "ghosts accepted")
	session.leave()
	check(session.role == "offline" and session.roster.is_empty() and session.phase == Party.Phase.LOBBY, "leave resets everything")
