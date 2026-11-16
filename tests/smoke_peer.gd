extends "res://tests/harness.gd"
## One real Iroh process per peer: a host and two clients play a one-round
## party match and must agree on every score.

const Party := preload("res://game/sim/party.gd")
const Flight := preload("res://game/sim/flight.gd")

var session: Node
var role_name := "peer"

func label() -> String:
	return role_name.to_upper()

func run() -> void:
	session = root.get_node("Session")
	var rooms: Node = root.get_node("Rooms")
	var args := OS.get_cmdline_user_args()
	role_name = args[0]
	var path := args[1]
	var use_codes := "--codes" in args
	session.player_name = role_name.capitalize()
	if role_name == "host":
		if use_codes:
			check(await rooms.host(), "host creates a join code")
		else:
			check(session.host(), "host starts")
		await create_timer(2.0).timeout
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(rooms.code if use_codes else session.ticket())
		file.close()
		check(await _wait(func() -> bool: return session.roster.size() >= 3, 60.0), "two clients joined")
		session.set_rounds(1)
		session.start_match()
		var mine := await _play(300, 800, "t40")
		check(await _wait(func() -> bool: return session.phase == Party.Phase.RESULTS, 60.0), "round resolved")
		check(session.entry(1).round_cm == mine, "host scored itself by replay")
		for row: Dictionary in session.roster:
			check(row.round_cm > 0, "%s has a verified distance" % row.name)
		session.advance()
		check(await _wait(func() -> bool: return session.phase == Party.Phase.FINAL, 5.0), "match reached the final")
		# Let clients read the final standings, then make sure they leave cleanly.
		check(await _wait(func() -> bool: return session.roster.size() == 1, 30.0), "clients left")
		var old_code: String = rooms.code
		session.leave()
		await create_timer(1.0).timeout
		if use_codes:
			var reply: Dictionary = await rooms.service.resolve(old_code)
			check(not reply.ok, "code revoked after leaving")
	else:
		var joined: bool = (await rooms.join(FileAccess.get_file_as_string(path))) if use_codes else session.join(FileAccess.get_file_as_string(path))
		check(joined, "client starts joining")
		check(await _wait(func() -> bool: return session.connected() and session.roster.size() >= 3, 60.0), "client sees the full party")
		check(not session.entry(session.local_id).is_empty(), "client is on the roster")
		var mine := await _play(450 + session.local_id % 7 * 10, 600, "t30d50")
		check(await _wait(func() -> bool: return session.phase == Party.Phase.FINAL, 60.0), "client saw the final")
		check(session.entry(session.local_id).round_cm == mine,
				"host's replay matches this client's flight: %d vs %d" % [session.entry(session.local_id).round_cm, mine])
		check(session.entry(1).round_cm > 0, "client sees the host's score")
		check(session.snapshots_received > 3, "ghost positions arrived")
		check(session.ghosts.has(1), "client sees the host's ghost")
		check(session.standings().size() == 3, "three players in the standings")
		# Stay a moment so the other client also sees a full table.
		await create_timer(1.5).timeout
		session.leave()
		await create_timer(0.5).timeout

## Waits for the round, flies it instantly with a fixed plan, reports it.
func _play(angle: int, power: int, plan: String) -> int:
	if not await _wait(func() -> bool: return session.phase == Party.Phase.PLAYING, 60.0):
		check(false, "round never started")
		return -1
	var flight: Flight = Flight.replay(session.round_seed, angle, power, Flight.decode_inputs(plan))
	for step in 8:
		session.report(flight.x * (step + 1) / 8.0, 3.0, session.FLYING)
		await create_timer(0.15).timeout
	session.report(flight.x, 0.0, session.LANDED)
	session.submit(angle, power, plan)
	return flight.distance_cm()

func _wait(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await create_timer(0.1).timeout
	return condition.call()
