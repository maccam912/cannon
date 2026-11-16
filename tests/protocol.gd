extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var session = root.get_node("Session")
	session.set_physics_process(false)
	session.role = "host"
	session.players[2] = Vector2(100, 100)
	session._receive(2, {"type":"input", "axis":[99999, 99999]})
	assert(session.inputs[2].length() <= 1.0001, "host must clamp movement")
	session._receive(3, {"type":"input", "axis":[1, 0]})
	assert(not session.inputs.has(3), "unknown peer cannot move")
	session._receive(2, {"type":"input", "axis":["bad", 0]})
	assert(session.inputs[2].length() <= 1.0001)
	session.role = "client"
	session._welcomed = true
	session._receive(2, {"type":"state", "players":[[1, 500, 500]]})
	assert(session.players[1] == Vector2(360, 240), "only host can publish state")
	session._receive(1, {"type":"state", "players":[[1, "bad", 500]]})
	assert(session.players[1] == Vector2(360, 240), "malformed snapshot is ignored")
	session._receive(1, {"type":"state", "players":[[1, 50, 60], [2, 90, 100]]})
	assert(session.players[1] == Vector2(50, 60))
	assert(session.snapshots_received == 1)
	session.leave()
	assert(session.role == "offline" and session.players.size() == 1)
	print("PROTOCOL_PASS")
	quit()
