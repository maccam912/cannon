extends SceneTree

var session: Node
var chat_seen := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	session = root.get_node("Session")
	session.chat_received.connect(func(message: String) -> void:
		if "smoke hello" in message:
			chat_seen = true)
	var args := OS.get_cmdline_user_args()
	var path := args[1]
	var use_codes := "--codes" in args
	var rooms := root.get_node("Rooms")
	if args[0] == "host":
		if use_codes:
			assert(await rooms.host(), "TEST FAIL: could not create join code")
		else:
			assert(session.host())
		await create_timer(2).timeout
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(rooms.code if use_codes else session.ticket())
		file.close()
		var joined := false
		for index in range(600):
			await create_timer(0.1).timeout
			if session.players.size() >= 3:
				joined = true
			if joined and session.players.size() == 1 and chat_seen:
				var old_code: String = rooms.code
				session.leave()
				await create_timer(1.0).timeout
				if use_codes:
					var reply: Dictionary = await rooms.service.resolve(old_code)
					assert(not reply.ok and "expired or not found" in str(reply.get("message", "")), "TEST FAIL: code not revoked")
				print("HOST_PASS")
				quit()
				return
		push_error("TEST FAIL: host did not see two peers, chat, and disconnect cleanup")
		quit(1)
	else:
		if use_codes:
			assert(await rooms.join(FileAccess.get_file_as_string(path)))
		else:
			assert(session.join(FileAccess.get_file_as_string(path)))
		for index in range(400):
			await create_timer(0.1).timeout
			if session.players.size() >= 3 and session.players.has(session.local_id):
				break
		assert(session.players.size() >= 3, "TEST FAIL: two clients must join")
		var start: Vector2 = session.players[session.local_id]
		session.direction = Vector2(1, 0)
		session.send_chat("smoke hello")
		await create_timer(1.2).timeout
		assert(session.snapshots_received > 10, "TEST FAIL: missing snapshots")
		assert(session.players[session.local_id].x > start.x + 80, "TEST FAIL: movement not replicated")
		assert(chat_seen, "TEST FAIL: reliable room chat not received")
		session.leave()
		await create_timer(0.5).timeout
		print("CLIENT_PASS")
		quit()
