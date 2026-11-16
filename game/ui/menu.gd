extends Control
## Title screen: name, solo, host a party, or join one with a code.

signal solo_pressed
signal host_pressed
signal join_pressed(code: String)
signal upgrades_pressed

const Style := preload("res://game/ui/style.gd")

var _name: LineEdit
var _code: LineEdit
var _status: Label
var _best: Label
var _sound: Button
var _main: VBoxContainer
var _join: VBoxContainer
var _busy := false
var _upgrades: Button
var _title: Label
var _tagline: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Style.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 40)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	_title = Style.label("CANNONAUTS", 104, Style.ORANGE, true)
	Style.outline(_title, 22)
	left.add_child(_title)
	_tagline = Style.label("Pump it. Fire it. Out-fly your friends.", 30)
	Style.outline(_tagline, 10)
	left.add_child(_tagline)
	get_viewport().size_changed.connect(_fit_title)
	_fit_title()
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	_best = Style.label("", 30, Style.CREAM, true)
	Style.outline(_best, 10)
	left.add_child(_best)
	var footer := HBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_theme_constant_override("separation", 16)
	left.add_child(footer)
	_sound = Style.button("", Style.SLATE, 20)
	_sound.custom_minimum_size = Vector2(170, 54)
	_sound.pressed.connect(func() -> void:
		Save.muted = not Save.muted
		Save.store()
		Sfx.apply_mute()
		refresh())
	footer.add_child(_sound)
	var version := Style.label("v" + str(ProjectSettings.get_setting("application/config/version", "dev")), 20, Color(Style.CREAM, 0.75))
	Style.outline(version, 6)
	version.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(version)

	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 420
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	panel.add_child(stack)

	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 14)
	stack.add_child(_main)
	_name = LineEdit.new()
	_name.placeholder_text = "Your name"
	_name.max_length = 12
	_name.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.custom_minimum_size.y = 58
	_name.text = Save.player_name
	_name.text_changed.connect(func(text: String) -> void:
		Save.player_name = text.strip_edges()
		Save.store())
	_main.add_child(_name)
	_add(_main, "SOLO LAUNCH", Style.ORANGE, func() -> void: solo_pressed.emit())
	_add(_main, "HOST A PARTY", Style.BLUE, func() -> void: host_pressed.emit())
	_upgrades = _add(_main, "UPGRADES", Style.PURPLE, func() -> void: upgrades_pressed.emit())
	_add(_main, "JOIN A PARTY", Style.GREEN, func() -> void: _show_join(true))

	_join = VBoxContainer.new()
	_join.add_theme_constant_override("separation", 14)
	_join.visible = false
	stack.add_child(_join)
	var prompt := Style.label("ENTER THE PARTY CODE", 24, Style.CREAM, true)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join.add_child(prompt)
	_code = LineEdit.new()
	_code.placeholder_text = "ABCD"
	_code.max_length = 8192
	_code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code.custom_minimum_size.y = 96
	_code.add_theme_font_override("font", Style.TITLE_FONT)
	_code.add_theme_font_size_override("font_size", 56)
	_code.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_code.text_changed.connect(func(text: String) -> void:
		# Codes are upper case; long pasted tickets are left untouched.
		if text.length() <= 4 and text != text.to_upper():
			var caret := _code.caret_column
			_code.text = text.to_upper()
			_code.caret_column = caret)
	_code.text_submitted.connect(func(_text: String) -> void: _submit_join())
	_join.add_child(_code)
	_add(_join, "JOIN", Style.GREEN, _submit_join)
	var extras := HBoxContainer.new()
	extras.add_theme_constant_override("separation", 14)
	_join.add_child(extras)
	var paste := _add(extras, "PASTE", Style.SLATE, func() -> void: _code.text = DisplayServer.clipboard_get().strip_edges())
	paste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back := _add(extras, "BACK", Style.SLATE, func() -> void: _show_join(false))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_status = Style.label("", 22, Color(1.0, 0.85, 0.5))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 360
	stack.add_child(_status)
	refresh()

## The title takes whatever width the button panel leaves, on any aspect ratio.
func _fit_title() -> void:
	var room := get_viewport_rect().size.x - 420.0 - 56.0 * 2.0 - 40.0 - 30.0
	var font: Font = Style.TITLE_FONT
	var title_size := clampi(int(104.0 * room / font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 104).x), 40, 110)
	_title.add_theme_font_size_override("font_size", title_size)
	var tag_size := clampi(int(30.0 * room / font.get_string_size(_tagline.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x), 16, 32)
	_tagline.add_theme_font_size_override("font_size", tag_size)

func _add(parent: Node, text: String, color: Color, action: Callable) -> Button:
	var button := Style.button(text, color)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _show_join(show: bool) -> void:
	_join.visible = show
	_main.visible = not show
	_status.text = ""
	if show and not DisplayServer.is_touchscreen_available():
		_code.grab_focus()

func _submit_join() -> void:
	var code := _code.text.strip_edges()
	if code.is_empty() or _busy:
		return
	_code.release_focus()
	join_pressed.emit(code)

func refresh() -> void:
	_best.text = "BEST  " + Style.meters(Save.best_cm) if Save.best_cm > 0 else ""
	_sound.text = "SOUND OFF" if Save.muted else "SOUND ON"
	# The star count, with a nudge when something is affordable.
	_upgrades.text = "UPGRADE%s  -  %d" % ["!" if Save.can_buy_any() else "S", Save.stars]

func set_status(text: String) -> void:
	_status.text = "" if text in ["Offline", "Connected", "Hosting"] else text

func set_busy(busy: bool) -> void:
	_busy = busy

func player_name() -> String:
	return _name.text.strip_edges()
