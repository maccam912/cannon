extends Node
## Party session over Iroh packet channels. Transport and wire protocol only:
## the match rules live in game/sim/party.gd and never touch the network.
##
## Host and clients expose the same mirrored view (phase, roster, ghosts), so
## screens read one shape regardless of role. See docs/NETWORKING.md.

signal status_changed(message: String)
signal session_closed
signal phase_changed
signal roster_changed

const Party := preload("res://game/sim/party.gd")

const PROTOCOL := 2
const CONNECT_TIMEOUT_MS := 18000
const MAX_PACKET := 1024
const INPUT_CHUNK := 800     # characters of input log per message
const MAX_INPUT_CHUNKS := 9
const GHOST_INTERVAL := 6   # physics ticks between position updates (10 Hz)
const AIMING := 0
const FLYING := 1
const LANDED := 2

var peer: MultiplayerPeer
var role := "offline"
var status := "Offline"
var local_id := 1
var player_name := "Player"

# Mirrored view, identical in shape on the host and on clients.
var phase: int = Party.Phase.LOBBY
var round_number := 0
var rounds := 3
var power := 0
var round_seed := 0
var phase_ends_msec := 0
## [{id, name, slot, total_cm, round_cm, best_cm, playing}] in join order.
var roster: Array = []
## id -> {x, y, state}: where every cannonaut currently is (cosmetic only).
var ghosts: Dictionary = {}

## Host only: the authoritative rules.
var party: Party
var pending: Dictionary = {}
var snapshots_received := 0

var _started_at := 0
var _welcomed := false
var _clock := 0
var _sent_phase := -1
var _sent_roster := -1
var _local_ghost := {"x": 0.0, "y": 0.0, "state": AIMING}
## Host: input logs arriving in pieces, sender -> {round, parts}.
var _input_parts: Dictionary = {}

func available() -> bool:
	if not ClassDB.class_exists("IrohServer") or not ClassDB.class_exists("IrohClient"):
		return false
	if OS.has_feature("android"):
		return Engine.has_singleton("IrohAndroid") and bool(Engine.get_singleton("IrohAndroid").call("initializeIroh"))
	return true

func host() -> bool:
	leave()
	if not available():
		_set_status("Multiplayer is unavailable in this build.")
		return false
	peer = ClassDB.class_call_static("IrohServer", "start_configured", "--relay-only" in OS.get_cmdline_user_args())
	if peer == null:
		_set_status("Could not start hosting. Check your network connection.")
		return false
	role = "host"
	local_id = Party.HOST_ID
	party = Party.new(int(Time.get_unix_time_from_system()) ^ (randi() << 8))
	party.add_player(local_id, player_name)
	peer.peer_connected.connect(_peer_connected)
	peer.peer_disconnected.connect(_peer_disconnected)
	_mirror_party()
	_set_status("Hosting")
	return true

func join(ticket: String) -> bool:
	leave()
	if not available():
		_set_status("Multiplayer is unavailable in this build.")
		return false
	ticket = ticket.strip_edges()
	if (not ticket.begins_with("git1_") and ticket.length() != 43) or ticket.length() > 8192:
		_set_status("That is not a valid code or ticket.")
		return false
	peer = ClassDB.class_call_static("IrohClient", "connect_configured", ticket, "--relay-only" in OS.get_cmdline_user_args())
	if peer == null:
		_set_status("Could not start connecting. Check your network connection.")
		return false
	role = "joining"
	local_id = 0
	_started_at = Time.get_ticks_msec()
	_set_status("Connecting...")
	return true

func ticket() -> String:
	return str(peer.call("connection_string")) if role == "host" and peer != null else ""

func leave() -> void:
	session_closed.emit()
	if peer != null:
		peer.close()
		peer = null
	var was_active := role != "offline"
	role = "offline"
	local_id = 1
	party = null
	pending.clear()
	ghosts.clear()
	_input_parts.clear()
	power = 0
	roster = []
	phase = Party.Phase.LOBBY
	round_number = 0
	round_seed = 0
	snapshots_received = 0
	_welcomed = false
	_clock = 0
	_sent_phase = -1
	_sent_roster = -1
	_set_status("Offline")
	if was_active:
		roster_changed.emit()
		phase_changed.emit()

func is_host() -> bool:
	return role == "host"

func connected() -> bool:
	return role == "host" or (role == "client" and _welcomed)

func entry(id: int) -> Dictionary:
	for row: Dictionary in roster:
		if row.id == id:
			return row
	return {}

## Roster ordered by match total, then best launch.
func standings() -> Array:
	var rows := roster.duplicate()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.total_cm != b.total_cm:
			return a.total_cm > b.total_cm
		if a.best_cm != b.best_cm:
			return a.best_cm > b.best_cm
		return a.id < b.id)
	return rows

func seconds_left() -> float:
	return maxf((phase_ends_msec - Time.get_ticks_msec()) / 1000.0, 0.0)

# --- Intent from the local player -------------------------------------------

func start_match() -> void:
	if role == "host":
		party.start(local_id)

func advance() -> void:
	if role == "host":
		party.advance(local_id)

func set_rounds(count: int) -> void:
	if role == "host":
		party.set_rounds(local_id, count)

func set_power(index: int) -> void:
	if role == "host":
		party.set_power(local_id, index)

## Where the local cannonaut is; shown to everyone else as a ghost.
func report(x: float, y: float, state: int) -> void:
	_local_ghost = {"x": x, "y": y, "state": state}
	if role == "host":
		ghosts[local_id] = _local_ghost

## What the local player did this round. The host replays it to get the score.
func submit(angle: int, pressure: int, inputs: String) -> void:
	if role == "host":
		party.submit(local_id, round_number, angle, pressure, inputs)
	elif role == "client" and _welcomed:
		# A long flight's log does not fit one packet, so it goes in pieces
		# on the ordered reliable channel, then the result closes it.
		var count := 0
		while count * INPUT_CHUNK < inputs.length():
			_send(1, {"type": "inputs", "r": round_number, "k": count, "i": inputs.substr(count * INPUT_CHUNK, INPUT_CHUNK)}, true)
			count += 1
		_send(1, {"type": "result", "r": round_number, "a": angle, "p": pressure, "n": count}, true)

# --- Transport ---------------------------------------------------------------

func _set_status(message: String) -> void:
	status = message
	status_changed.emit(message)

func _peer_connected(id: int) -> void:
	pending[id] = Time.get_ticks_msec()

func _peer_disconnected(id: int) -> void:
	pending.erase(id)
	ghosts.erase(id)
	_input_parts.erase(id)
	if party != null:
		party.remove_player(id)

func _physics_process(_delta: float) -> void:
	if peer == null:
		return
	peer.poll()
	var connection := peer.get_connection_status()
	if connection == MultiplayerPeer.CONNECTION_DISCONNECTED:
		var reason := str(peer.call("connection_error")) if peer.has_method("connection_error") else ""
		var lost := "The host left the party." if role == "client" else "Disconnected."
		leave()
		_set_status((lost + " " + reason).strip_edges())
		return
	if role == "joining" and connection == MultiplayerPeer.CONNECTION_CONNECTED:
		local_id = peer.get_unique_id()
		role = "client"
		_send(1, {"type": "hello", "version": PROTOCOL, "name": player_name}, true)
	if role in ["joining", "client"] and not _welcomed and Time.get_ticks_msec() - _started_at > CONNECT_TIMEOUT_MS:
		leave()
		_set_status("Could not reach the party. Ask the host for a fresh code.")
		return
	for _index in range(mini(peer.get_available_packet_count(), 256)):
		var sender := peer.get_packet_peer()
		var packet := peer.get_packet()
		if packet.size() > MAX_PACKET:
			continue
		var parser := JSON.new()
		if parser.parse(packet.get_string_from_utf8()) == OK and parser.data is Dictionary:
			_receive(sender, parser.data)
		if peer == null:
			return
	_clock += 1
	if role == "host":
		party.tick()
		_publish()
		if _clock % GHOST_INTERVAL == 0:
			if phase == Party.Phase.PLAYING:
				_send(0, {"type": "ghosts", "r": round_number, "g": _ghost_rows()}, false)
			for id: int in pending.keys():
				if Time.get_ticks_msec() - int(pending[id]) > 5000:
					peer.disconnect_peer(id, true)
					_peer_disconnected(id)
	elif role == "client" and _welcomed and _clock % GHOST_INTERVAL == 0 and phase == Party.Phase.PLAYING:
		_send(1, {"type": "pos", "r": round_number, "x": snappedf(_local_ghost.x, 0.01),
				"y": snappedf(_local_ghost.y, 0.01), "s": _local_ghost.state}, false)

## Host: copy rule state into the mirrored view and tell clients what changed.
func _publish() -> void:
	if party.phase_revision != _sent_phase:
		_sent_phase = party.phase_revision
		if party.phase in [Party.Phase.COUNTDOWN, Party.Phase.LOBBY]:
			ghosts.clear()
			_input_parts.clear()
		_mirror_party()
		_send(0, _phase_message(), true)
		phase_changed.emit()
	if party.roster_revision != _sent_roster:
		_sent_roster = party.roster_revision
		_mirror_party()
		_send(0, _roster_message(), true)
		roster_changed.emit()

func _mirror_party() -> void:
	phase = party.phase
	round_number = party.round_number
	rounds = party.rounds
	power = party.power
	round_seed = party.round_seed
	phase_ends_msec = Time.get_ticks_msec() + party.ticks_left() * 1000 / 60
	roster = []
	for id: int in party.players:
		var player: Dictionary = party.players[id]
		roster.append({"id": id, "name": player.name, "slot": player.slot, "total_cm": player.total_cm,
				"round_cm": player.round_cm, "best_cm": player.best_cm, "playing": player.playing})

func _phase_message() -> Dictionary:
	return {"type": "phase", "ph": party.phase, "r": party.round_number, "n": party.rounds,
			"u": party.power, "seed": party.round_seed, "t": party.ticks_left()}

func _roster_message() -> Dictionary:
	var rows: Array = []
	for row: Dictionary in roster:
		rows.append([row.id, row.name, row.slot, row.total_cm, row.round_cm, row.best_cm, 1 if row.playing else 0])
	return {"type": "roster", "p": rows}

func _ghost_rows() -> Array:
	var rows: Array = []
	for id: int in ghosts:
		var ghost: Dictionary = ghosts[id]
		rows.append([id, snappedf(ghost.x, 0.01), snappedf(ghost.y, 0.01), ghost.state])
	return rows

func _receive(sender: int, message: Dictionary) -> void:
	var kind: Variant = message.get("type")
	if role == "host":
		if kind == "hello" and pending.has(sender):
			if message.get("version") != PROTOCOL or not party.add_player(sender, str(message.get("name", "")).left(24)):
				if peer != null:
					peer.disconnect_peer(sender, true)
				_peer_disconnected(sender)
				return
			pending.erase(sender)
			_send(sender, {"type": "welcome", "version": PROTOCOL}, true)
			# Catch the newcomer up; everyone else just hears it again.
			_send(sender, _phase_message(), true)
		elif party.players.has(sender):
			if kind == "pos":
				if message.get("r") == round_number and _number(message.get("x")) and _number(message.get("y")) and message.get("s") in [0.0, 1.0, 2.0]:
					ghosts[sender] = {"x": clampf(float(message.x), 0.0, 1000000.0),
							"y": clampf(float(message.y), 0.0, 10000.0), "state": int(message.s)}
			elif kind == "inputs":
				_accept_inputs(sender, message)
			elif kind == "result":
				var received: Dictionary = _input_parts.get(sender, {})
				_input_parts.erase(sender)
				var parts: Array = received.get("parts", []) if received.get("round") == message.get("r") else []
				if message.get("n") == parts.size():
					party.submit(sender, message.get("r"), message.get("a"), message.get("p"), "".join(parts))
	elif role == "client" and sender == Party.HOST_ID:
		if kind == "welcome" and message.get("version") == PROTOCOL:
			_welcomed = true
			_set_status("Connected")
		elif not _welcomed:
			return
		elif kind == "phase":
			_accept_phase(message)
		elif kind == "roster":
			_accept_roster(message.get("p"))
		elif kind == "ghosts":
			_accept_ghosts(message)

## Host: one piece of a client's input log. Pieces must arrive in order for
## the current round, and there is a hard cap on how many.
func _accept_inputs(sender: int, message: Dictionary) -> void:
	var piece: Variant = message.get("i")
	if message.get("r") != round_number or not piece is String or piece.length() > INPUT_CHUNK or not _whole(message.get("k")):
		_input_parts.erase(sender)
		return
	var received: Dictionary = _input_parts.get(sender, {})
	if received.get("round") != round_number:
		received = {"round": round_number, "parts": []}
	if int(message.k) != received.parts.size() or received.parts.size() >= MAX_INPUT_CHUNKS:
		_input_parts.erase(sender)
		return
	received.parts.append(piece)
	_input_parts[sender] = received

func _accept_phase(message: Dictionary) -> void:
	for key in ["ph", "r", "n", "u", "seed", "t"]:
		if not _whole(message.get(key)):
			return
	if int(message.ph) < 0 or int(message.ph) >= Party.Phase.size() or int(message.r) < 0 or int(message.r) > 99 or not int(message.n) in Party.ROUND_CHOICES or int(message.u) < 0 or int(message.u) > 2 or int(message.t) < 0 or int(message.t) > Party.ROUND_TICKS:
		return
	phase = int(message.ph)
	round_number = int(message.r)
	rounds = int(message.n)
	power = int(message.u)
	round_seed = int(message.seed)
	phase_ends_msec = Time.get_ticks_msec() + int(message.t) * 1000 / 60
	if phase in [Party.Phase.COUNTDOWN, Party.Phase.LOBBY]:
		ghosts.clear()
	phase_changed.emit()

func _accept_roster(rows: Variant) -> void:
	if not rows is Array or rows.size() > Party.MAX_PLAYERS:
		return
	var next: Array = []
	for row: Variant in rows:
		if not row is Array or row.size() != 7 or not row[1] is String:
			return
		for index in [0, 2, 3, 4, 5, 6]:
			if not _whole(row[index]):
				return
		if int(row[0]) < 1 or int(row[2]) < 0 or int(row[2]) >= Party.MAX_PLAYERS or int(row[3]) < 0 or int(row[4]) < -1 or int(row[5]) < 0:
			return
		next.append({"id": int(row[0]), "name": Party.clean_name(row[1], int(row[0])), "slot": int(row[2]),
				"total_cm": int(row[3]), "round_cm": int(row[4]), "best_cm": int(row[5]), "playing": int(row[6]) == 1})
	roster = next
	for id: int in ghosts.keys():
		if entry(id).is_empty():
			ghosts.erase(id)
	roster_changed.emit()

func _accept_ghosts(message: Dictionary) -> void:
	var rows: Variant = message.get("g")
	if message.get("r") != round_number or not rows is Array or rows.size() > Party.MAX_PLAYERS:
		return
	for row: Variant in rows:
		if not row is Array or row.size() != 4 or not _whole(row[0]) or not _number(row[1]) or not _number(row[2]) or not row[3] in [0.0, 1.0, 2.0]:
			return
	for row: Array in rows:
		ghosts[int(row[0])] = {"x": clampf(float(row[1]), 0.0, 1000000.0), "y": clampf(float(row[2]), 0.0, 10000.0), "state": int(row[3])}
	snapshots_received += 1

func _send(target: int, message: Dictionary, reliable: bool) -> void:
	if peer == null:
		return
	var packet := JSON.stringify(message).to_utf8_buffer()
	if packet.size() > MAX_PACKET:
		push_warning("Dropped an oversized %s message" % message.get("type"))
		return
	peer.set_target_peer(target)
	peer.transfer_channel = 0 if reliable else 1
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	var error := peer.put_packet(packet)
	if reliable and error != OK:
		_set_status("Network send failed (%d). Rejoin if it persists." % error)

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _whole(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and absf(float(value)) < 4294967296.0

func _exit_tree() -> void:
	if peer != null:
		peer.close()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and OS.has_feature("mobile") and role != "offline":
		leave()
		_set_status("The party closed while the app was in the background.")
