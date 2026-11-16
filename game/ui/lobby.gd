extends Control
## Party lobby: the code to share, who is in, and the host's start controls.

signal leave_pressed

const Style := preload("res://game/ui/style.gd")
const Party := preload("res://game/sim/party.gd")
const Upgrades := preload("res://game/sim/upgrades.gd")

var _code: Label
var _expiry: Label
var _players: GridContainer
var _rounds: HBoxContainer
var _power: HBoxContainer
var _start: Button
var _hint: Label
var _share: HBoxContainer
var _signature := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Style.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	centre.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	panel.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size.x = 340
	row.add_child(left)
	left.add_child(Style.label("PARTY CODE", 26, Color(Style.CREAM, 0.75), true))
	_code = Style.label("----", 120, Style.ORANGE, true)
	left.add_child(_code)
	_expiry = Style.label("", 22, Color(Style.CREAM, 0.75))
	_expiry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_expiry)
	_share = HBoxContainer.new()
	_share.add_theme_constant_override("separation", 12)
	left.add_child(_share)
	var copy_code := Style.button("COPY CODE", Style.SLATE, 20)
	copy_code.pressed.connect(func() -> void:
		if not Rooms.code.is_empty():
			DisplayServer.clipboard_set(Rooms.code)
			_hint.text = "Code copied.")
	_share.add_child(copy_code)
	var copy_ticket := Style.button("COPY TICKET", Style.SLATE, 20)
	copy_ticket.pressed.connect(func() -> void:
		if not Session.ticket().is_empty():
			DisplayServer.clipboard_set(Session.ticket())
			_hint.text = "Ticket copied. It works even if codes are down.")
	_share.add_child(copy_ticket)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(gap)
	_hint = Style.label("", 22, Color(1.0, 0.85, 0.5))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(340, 60)
	left.add_child(_hint)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	right.add_child(Style.label("CANNONAUTS", 26, Color(Style.CREAM, 0.75), true))
	_players = GridContainer.new()
	_players.columns = 2
	_players.add_theme_constant_override("h_separation", 10)
	_players.add_theme_constant_override("v_separation", 8)
	right.add_child(_players)
	_rounds = HBoxContainer.new()
	_rounds.add_theme_constant_override("separation", 10)
	right.add_child(_rounds)
	_power = HBoxContainer.new()
	_power.add_theme_constant_override("separation", 10)
	right.add_child(_power)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	right.add_child(buttons)
	var leave := Style.button("LEAVE", Style.SLATE)
	leave.pressed.connect(func() -> void: leave_pressed.emit())
	buttons.add_child(leave)
	_start = Style.button("START", Style.ORANGE)
	_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start.pressed.connect(func() -> void: Session.start_match())
	buttons.add_child(_start)
	Session.roster_changed.connect(refresh)
	Session.phase_changed.connect(refresh)
	Rooms.changed.connect(refresh)

func _process(_delta: float) -> void:
	if not visible:
		return
	var host := Session.is_host()
	if Rooms.code.is_empty():
		_code.text = "----"
		_expiry.text = ("Getting a code..." if Rooms.busy else "No code right now. Share the ticket instead.") if host else "You are in."
	else:
		_code.text = Rooms.code
		var seconds := int(Rooms.expires_at - Time.get_unix_time_from_system())
		if seconds > 0:
			_expiry.text = "Friends enter this on Join a Party.  New code in %d:%02d" % [seconds / 60, seconds % 60]
		elif host and not Rooms.busy:
			# Keep the door open for as long as the lobby is.
			Rooms.refresh_code()

func refresh() -> void:
	if not is_inside_tree():
		return
	var host := Session.is_host()
	_share.visible = host
	_start.visible = host
	_code.visible = host
	if not host:
		_hint.text = "Waiting for the host to start..."
	elif _hint.text.begins_with("Waiting"):
		_hint.text = ""
	# Rebuild only when something visible changed, so taps are never eaten.
	var signature := str(Session.roster.map(func(row: Dictionary) -> String: return "%d%s%d" % [row.id, row.name, row.slot])) + str(Session.rounds) + str(Session.power) + str(host) + str(Session.local_id)
	if signature == _signature:
		return
	_signature = signature
	for child: Node in _players.get_children():
		_players.remove_child(child)
		child.queue_free()
	for seat in Party.MAX_PLAYERS:
		var chip := PanelContainer.new()
		chip.custom_minimum_size = Vector2(230, 50)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		chip.add_child(line)
		if seat < Session.roster.size():
			var row: Dictionary = Session.roster[seat]
			chip.add_theme_stylebox_override("panel", Style.panel(Color(Style.seat_color(row.slot), 0.3), 14))
			var face := TextureRect.new()
			face.texture = Style.alien(row.slot)
			face.custom_minimum_size = Vector2(40, 40)
			face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			line.add_child(face)
			var who := Style.label(row.name, 24, Style.CREAM, true)
			who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(who)
			var tags: Array = []
			if row.id == Session.local_id:
				tags.append("you")
			if row.id == Party.HOST_ID:
				tags.append("host")
			line.add_child(Style.label(" - ".join(tags), 18, Color(Style.CREAM, 0.65)))
		else:
			chip.add_theme_stylebox_override("panel", Style.panel(Color(1, 1, 1, 0.05), 14))
			line.add_child(Style.label("open seat", 22, Color(Style.CREAM, 0.3)))
		_players.add_child(chip)
	for child: Node in _rounds.get_children():
		_rounds.remove_child(child)
		child.queue_free()
	var caption := Style.label("ROUNDS", 24, Color(Style.CREAM, 0.75), true)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rounds.add_child(caption)
	for count: int in Party.ROUND_CHOICES:
		if host:
			var pick := Style.button(str(count), Style.BLUE if count == Session.rounds else Style.SLATE, 26)
			pick.custom_minimum_size = Vector2(84, 54)
			pick.pressed.connect(func() -> void: Session.set_rounds(count))
			_rounds.add_child(pick)
		elif count == Session.rounds:
			_rounds.add_child(Style.label(str(count), 30, Style.CREAM, true))
	# Everyone flies the same upgrade level, picked by the host.
	for child: Node in _power.get_children():
		_power.remove_child(child)
		child.queue_free()
	var power_caption := Style.label("POWER", 24, Color(Style.CREAM, 0.75), true)
	power_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_power.add_child(power_caption)
	for index in Upgrades.PRESET_NAMES.size():
		if host:
			var choice := Style.button(Upgrades.PRESET_NAMES[index], Style.PURPLE if index == Session.power else Style.SLATE, 20)
			choice.custom_minimum_size = Vector2(110, 54)
			choice.pressed.connect(func() -> void: Session.set_power(index))
			_power.add_child(choice)
		elif index == Session.power:
			_power.add_child(Style.label(Upgrades.PRESET_NAMES[index], 26, Style.CREAM, true))
