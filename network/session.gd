extends Node
## Host-authoritative demo protocol over Iroh packet channels.
## Transport is deliberately separate from gameplay; see docs/NETWORKING.md.

signal status_changed(message: String)
signal chat_received(message: String)
signal session_closed

const PROTOCOL := 1
const SPEED := 190.0
const ARENA := Vector2(720, 480)
const MAX_PLAYERS := 8
const CONNECT_TIMEOUT_MS := 18000

var peer: MultiplayerPeer
var role := "offline"
var status := "Offline playground"
var local_id := 1
var players: Dictionary = {1: Vector2(360, 240)}
var direction := Vector2.ZERO
var inputs: Dictionary = {}
var input_times: Dictionary = {}
var pending: Dictionary = {}
var last_chat: Dictionary = {}
var snapshots_received := 0
var _send_clock := 0.0
var _started_at := 0
var _welcomed := false

func available() -> bool:
	if not ClassDB.class_exists("IrohServer") or not ClassDB.class_exists("IrohClient"):
		return false
	if OS.has_feature("android"):
		return Engine.has_singleton("IrohAndroid") and bool(Engine.get_singleton("IrohAndroid").call("initializeIroh"))
	return true

func host() -> bool:
	leave()
	if not available():
		_set_status("Build the native extension first: python3 tools/build_native.py")
		return false
	peer = ClassDB.class_call_static("IrohServer", "start_configured", "--relay-only" in OS.get_cmdline_user_args())
	if peer == null:
		_set_status("Could not start Iroh. Check the console and network access.")
		return false
	role = "host"
	peer.peer_connected.connect(_peer_connected)
	peer.peer_disconnected.connect(_peer_disconnected)
	_set_status("Hosting · share your connection ticket")
	return true

func join(ticket: String) -> bool:
	leave()
	if not available():
		_set_status("Iroh extension unavailable on this build.")
		return false
	ticket = ticket.strip_edges()
	if (not ticket.begins_with("git1_") and ticket.length() != 43) or ticket.length() > 8192:
		_set_status("Paste a complete git1_ connection ticket.")
		return false
	peer = ClassDB.class_call_static("IrohClient", "connect_configured", ticket, "--relay-only" in OS.get_cmdline_user_args())
	role = "joining"
	players.clear()
	local_id = 0
	_started_at = Time.get_ticks_msec()
	_set_status("Connecting…")
	return true

func ticket() -> String:
	return str(peer.call("connection_string")) if role == "host" and peer != null else ""

func leave() -> void:
	session_closed.emit()
	if peer != null:
		peer.close()
		peer = null
	role = "offline"
	local_id = 1
	players = {1: Vector2(360, 240)}
	inputs.clear()
	input_times.clear()
	pending.clear()
	last_chat.clear()
	direction = Vector2.ZERO
	_welcomed = false
	_send_clock = 0.0
	snapshots_received = 0
	_set_status("Offline playground")

func _set_status(message: String) -> void:
	status = message
	status_changed.emit(message)

func _peer_connected(id: int) -> void:
	pending[id] = Time.get_ticks_msec()

func _peer_disconnected(id: int) -> void:
	players.erase(id)
	inputs.erase(id)
	input_times.erase(id)
	pending.erase(id)
	last_chat.erase(id)

func _physics_process(delta: float) -> void:
	if peer != null:
		peer.poll()
		var connection := peer.get_connection_status()
		if connection == MultiplayerPeer.CONNECTION_DISCONNECTED:
			var reason := str(peer.call("connection_error")) if peer.has_method("connection_error") else ""
			leave()
			_set_status("Disconnected. " + reason)
			return
		if role == "joining" and connection == MultiplayerPeer.CONNECTION_CONNECTED:
			local_id = peer.get_unique_id()
			role = "client"
			_send(1, {"type":"hello", "version":PROTOCOL}, true)
		if role in ["joining", "client"] and not _welcomed and Time.get_ticks_msec() - _started_at > CONNECT_TIMEOUT_MS:
			leave()
			_set_status("Connection timed out. Ask the host for a fresh ticket.")
			return
		for _index in range(mini(peer.get_available_packet_count(), 256)):
			var sender := peer.get_packet_peer()
			var packet := peer.get_packet()
			if packet.size() > 1024:
				continue
			var parser := JSON.new()
			if parser.parse(packet.get_string_from_utf8()) == OK and parser.data is Dictionary:
				_receive(sender, parser.data)
	if role in ["host", "offline"]:
		inputs[1] = direction.limit_length()
		for id: int in players.keys():
			var axis: Vector2 = inputs.get(id, Vector2.ZERO)
			if id != 1 and Time.get_ticks_msec() - int(input_times.get(id, 0)) > 500:
				axis = Vector2.ZERO
			players[id] = (players[id] + axis * SPEED * delta).clamp(Vector2(18, 18), ARENA - Vector2(18, 18))
	_send_clock += delta
	if _send_clock >= 0.05:
		_send_clock = 0.0
		if role == "host":
			var rows: Array = []
			for id: int in players:
				var position: Vector2 = players[id]
				rows.append([id, snappedf(position.x, 0.1), snappedf(position.y, 0.1)])
			_send(0, {"type":"state", "players":rows}, false)
			for id: int in pending.keys():
				if Time.get_ticks_msec() - int(pending[id]) > 5000:
					peer.disconnect_peer(id, true)
					_peer_disconnected(id)
		elif role == "client" and _welcomed:
			_send(1, {"type":"input", "axis":[direction.x, direction.y]}, false)

func _receive(sender: int, message: Dictionary) -> void:
	var kind = message.get("type")
	if role == "host":
		if kind == "hello" and pending.has(sender):
			if message.get("version") != PROTOCOL or players.size() >= MAX_PLAYERS:
				peer.disconnect_peer(sender, true)
				_peer_disconnected(sender)
				return
			pending.erase(sender)
			players[sender] = Vector2(80 + (sender % 6) * 90, 240)
			_send(sender, {"type":"welcome", "version":PROTOCOL}, true)
			chat_received.emit("Player %d joined" % sender)
		elif players.has(sender):
			if kind == "input":
				var axis = message.get("axis")
				if _valid_vector(axis):
					inputs[sender] = Vector2(float(axis[0]), float(axis[1])).limit_length()
					input_times[sender] = Time.get_ticks_msec()
			elif kind == "chat":
				_accept_chat(sender, message.get("text"))
	elif role == "client" and sender == 1:
		if kind == "welcome" and message.get("version") == PROTOCOL:
			_welcomed = true
			_set_status("Connected · player %d" % local_id)
		elif kind == "state" and _welcomed:
			var rows = message.get("players")
			if not rows is Array or rows.size() > MAX_PLAYERS:
				return
			var next: Dictionary = {}
			for row in rows:
				if not row is Array or row.size() != 3 or not _number(row[0]) or float(row[0]) != floorf(float(row[0])) or float(row[0]) < 1 or float(row[0]) > 2147483647 or not _valid_vector([row[1], row[2]]):
					return
				next[int(row[0])] = Vector2(float(row[1]), float(row[2])).clamp(Vector2.ZERO, ARENA)
			players = next
			snapshots_received += 1
		elif kind == "chat" and message.get("text") is String:
			chat_received.emit(str(message.text).left(200))

func send_chat(text: String) -> void:
	text = text.strip_edges().left(160)
	if text.is_empty():
		return
	if role in ["host", "offline"]:
		_accept_chat(1, text)
	elif role == "client" and _welcomed:
		_send(1, {"type":"chat", "text":text}, true)

func _accept_chat(sender: int, value: Variant) -> void:
	if not value is String or value.length() > 160 or value.strip_edges().is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - int(last_chat.get(sender, -1000)) < 750:
		return
	last_chat[sender] = now
	var text := "Player %d: %s" % [sender, value.strip_edges()]
	chat_received.emit(text)
	if role == "host":
		_send(0, {"type":"chat", "text":text}, true)

func _send(target: int, message: Dictionary, reliable: bool) -> void:
	if peer == null:
		return
	var packet := JSON.stringify(message).to_utf8_buffer()
	if packet.size() > 1024:
		return
	peer.set_target_peer(target)
	peer.transfer_channel = 0 if reliable else 1
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	var error := peer.put_packet(packet)
	if reliable and error != OK:
		_set_status("Network send failed (%d). Reconnect if it persists." % error)

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _valid_vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])

func _exit_tree() -> void:
	if peer != null:
		peer.close()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and OS.has_feature("mobile") and role != "offline":
		leave()
		_set_status("Session closed while app was in the background. Host or join again.")
