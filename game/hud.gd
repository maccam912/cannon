extends Control
## In-game overlay and the tap surface. Everything is sized for thumbs first:
## during a flight the left half of the screen dives and the right half
## thrusts, so no small button ever has to be hit.

signal primary     # pump / fire / thrust
signal secondary   # dive
signal menu_pressed

const Style := preload("res://game/ui/style.gd")
const Aim := preload("res://game/sim/aim.gd")
const Flight := preload("res://game/sim/flight.gd")

var flying := false   # true while taps mean thrust/dive rather than pump/fire

var _margin: MarginContainer
var _distance: Label
var _detail: Label
var _info: Label
var _board: VBoxContainer
var _banner: Label
var _sub_banner: Label
var _gauge: Control
var _hints: Control
var _result: PanelContainer
var _menu: Button
var _aim: Aim
var _thrusts := 0
var _hint_flash := {"thrust": 0.0, "dive": 0.0}
var _banner_until := 0.0
var _menu_armed_until := 0.0
var _touch_device := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Style.theme()
	_touch_device = DisplayServer.is_touchscreen_available()
	_hints = Control.new()
	_hints.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.draw.connect(_draw_hints)
	add_child(_hints)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(layer)

	_distance = Style.label("", 64, Style.CREAM, true)
	Style.outline(_distance, 14)
	_distance.position = Vector2(8, -8)
	layer.add_child(_distance)
	_detail = Style.label("", 26)
	Style.outline(_detail, 8)
	_detail.position = Vector2(12, 66)
	layer.add_child(_detail)

	_info = Style.label("", 28, Style.CREAM, true)
	Style.outline(_info, 8)
	_info.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_info.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.offset_top = 8
	layer.add_child(_info)

	var corner := VBoxContainer.new()
	corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.alignment = BoxContainer.ALIGNMENT_BEGIN
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.add_theme_constant_override("separation", 10)
	layer.add_child(corner)
	_menu = Style.button("MENU", Style.SLATE, 22)
	_menu.custom_minimum_size = Vector2(130, 56)
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_END
	_menu.pressed.connect(_on_menu)
	corner.add_child(_menu)
	_board = VBoxContainer.new()
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_theme_constant_override("separation", 2)
	corner.add_child(_board)

	_banner = Style.label("", 110, Style.CREAM, true)
	Style.outline(_banner, 20)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.offset_top = -150
	_banner.offset_bottom = -150
	layer.add_child(_banner)
	_sub_banner = Style.label("", 34, Style.CREAM, true)
	Style.outline(_sub_banner, 10)
	_sub_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_sub_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sub_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_banner.offset_top = -60
	layer.add_child(_sub_banner)

	_gauge = Control.new()
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_gauge.custom_minimum_size = Vector2(620, 190)
	_gauge.offset_left = -310
	_gauge.offset_right = 310
	_gauge.offset_top = -210
	_gauge.offset_bottom = -20
	_gauge.draw.connect(_draw_gauge)
	_gauge.visible = false
	layer.add_child(_gauge)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_result = PanelContainer.new()
	_result.pivot_offset_ratio = Vector2(0.5, 0.5)
	_result.visible = false
	centre.add_child(_result)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()

## Keeps widgets out from under notches and rounded corners.
func _apply_safe_area() -> void:
	var window := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	var view := get_viewport_rect().size
	var left := 16.0
	var top := 10.0
	var right := 16.0
	var bottom := 10.0
	if OS.has_feature("mobile") and window.x > 0 and window.y > 0 and safe.size.x > 0:
		var scale_factor := view / window
		left += maxf(safe.position.x, 0.0) * scale_factor.x
		top += maxf(safe.position.y, 0.0) * scale_factor.y
		right += maxf(window.x - safe.end.x, 0.0) * scale_factor.x
		bottom += maxf(window.y - safe.end.y, 0.0) * scale_factor.y
	_margin.add_theme_constant_override("margin_left", int(left))
	_margin.add_theme_constant_override("margin_top", int(top))
	_margin.add_theme_constant_override("margin_right", int(right))
	_margin.add_theme_constant_override("margin_bottom", int(bottom))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_tap(event.position.x < size.x / 2.0)
	elif event is InputEventMouseButton and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_tap(event.position.x < size.x / 2.0)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			secondary.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_pressed() or event.is_echo():
		return
	var key := event as InputEventKey
	if key.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_UP, KEY_W, KEY_D, KEY_RIGHT]:
		primary.emit()
	elif key.physical_keycode in [KEY_DOWN, KEY_S, KEY_A, KEY_LEFT, KEY_SHIFT]:
		secondary.emit()

func _tap(left_half: bool) -> void:
	if flying and left_half:
		secondary.emit()
	else:
		primary.emit()

func _on_menu() -> void:
	# Two taps to leave, so a stray thumb never ends a run.
	var now := Time.get_ticks_msec() / 1000.0
	if now < _menu_armed_until:
		_menu_armed_until = 0.0
		_menu.text = "MENU"
		menu_pressed.emit()
	else:
		_menu_armed_until = now + 2.5
		_menu.text = "QUIT?"

func reset() -> void:
	flying = false
	_aim = null
	_gauge.visible = false
	_result.visible = false
	_distance.text = ""
	_detail.text = ""
	_banner.text = ""
	_sub_banner.text = ""
	_banner_until = 0.0
	set_board([])

func set_info(text: String) -> void:
	_info.text = text

func show_aim(aim: Aim) -> void:
	_aim = aim
	_gauge.visible = aim != null

func set_flight(distance: float, height: float, speed: float, thrusts: int) -> void:
	_distance.text = "%d m" % int(distance)
	_detail.text = "%d m up   %d m/s" % [int(height), int(speed)]
	_thrusts = thrusts

func flash_hint(which: String) -> void:
	_hint_flash[which] = 1.0

## Big centre text; seconds = 0 keeps it until replaced.
func show_banner(text: String, sub: String = "", seconds: float = 0.0, color: Color = Style.CREAM) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_sub_banner.text = sub
	_banner_until = Time.get_ticks_msec() / 1000.0 + seconds if seconds > 0.0 else 0.0
	_banner.pivot_offset_ratio = Vector2(0.5, 0.5)
	_banner.scale = Vector2.ONE * 1.5
	create_tween().tween_property(_banner, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Live standings: [{name, slot, text, me}].
func set_board(rows: Array) -> void:
	while _board.get_child_count() > rows.size():
		var extra := _board.get_child(_board.get_child_count() - 1)
		_board.remove_child(extra)
		extra.queue_free()
	while _board.get_child_count() < rows.size():
		var label := Style.label("", 24, Style.CREAM, true)
		Style.outline(label, 8)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_board.add_child(label)
	for index in rows.size():
		var row: Dictionary = rows[index]
		var label: Label = _board.get_child(index)
		label.text = "%s  %s" % [row.name, row.text]
		label.add_theme_color_override("font_color", Style.seat_color(row.slot))
		label.add_theme_font_size_override("font_size", 28 if row.me else 22)

## Centre panel. rows: [{slot, name, text, note, me}], buttons: [[text, color, callable]].
func show_result(title: String, big: String, sub: String, rows: Array, buttons: Array, title_color: Color = Style.ORANGE) -> void:
	for child: Node in _result.get_children():
		_result.remove_child(child)
		child.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size.x = 560
	_result.add_child(box)
	var heading := Style.label(title, 38, title_color, true)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	if not big.is_empty():
		var number := Style.label(big, 84, Style.CREAM, true)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(number)
	if not sub.is_empty():
		var line := Style.label(sub, 26, Color(Style.CREAM, 0.8))
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(line)
	for index in rows.size():
		var row: Dictionary = rows[index]
		var strip := PanelContainer.new()
		strip.add_theme_stylebox_override("panel", Style.panel(Color(Style.seat_color(row.slot), 0.28 if row.me else 0.12), 12))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		strip.add_child(line)
		line.add_child(Style.label("%d" % (index + 1), 28, Style.CREAM, true))
		var face := TextureRect.new()
		face.texture = Style.alien(row.slot)
		face.custom_minimum_size = Vector2(40, 40)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		line.add_child(face)
		var who := Style.label(row.name, 28, Style.seat_color(row.slot), true)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(who)
		if not str(row.get("note", "")).is_empty():
			line.add_child(Style.label(row.note, 22, Color(Style.CREAM, 0.7)))
		line.add_child(Style.label(row.text, 30, Style.CREAM, true))
		box.add_child(strip)
	if not buttons.is_empty():
		var bar := HBoxContainer.new()
		bar.add_theme_constant_override("separation", 14)
		bar.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_child(bar)
		for entry: Array in buttons:
			var button := Style.button(entry[0], entry[1])
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.pressed.connect(entry[2])
			bar.add_child(button)
	_result.visible = true
	_result.scale = Vector2.ONE * 0.8
	_result.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(_result, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_result, "modulate:a", 1.0, 0.15)

func hide_result() -> void:
	_result.visible = false

func result_visible() -> bool:
	return _result.visible

func _process(delta: float) -> void:
	for which: String in _hint_flash:
		_hint_flash[which] = maxf(_hint_flash[which] - delta * 3.0, 0.0)
	if _banner_until > 0.0 and Time.get_ticks_msec() / 1000.0 > _banner_until:
		_banner_until = 0.0
		_banner.text = ""
		_sub_banner.text = ""
	if _menu_armed_until > 0.0 and Time.get_ticks_msec() / 1000.0 > _menu_armed_until:
		_menu_armed_until = 0.0
		_menu.text = "MENU"
	_gauge.queue_redraw()
	_hints.queue_redraw()

func _draw_gauge() -> void:
	if _aim == null:
		return
	var font: Font = Style.TITLE_FONT
	var width := _gauge.size.x
	var pumping := _aim.stage == Aim.Stage.PUMP
	var prompt := "TAP WHEN FULL!" if pumping else "TAP TO FIRE!"
	var pulse := 1.0 + sin(Time.get_ticks_msec() / 90.0) * 0.04
	_text(font, Vector2(width / 2.0, 34), prompt, int(40 * pulse), Style.CREAM)
	# Three pump lamps.
	for index in Aim.PUMPS:
		var centre := Vector2(width / 2.0 + (index - 1) * 74.0, 78)
		_gauge.draw_circle(centre, 24, Color(Style.NAVY, 0.9))
		if index < _aim.scores.size():
			var score: float = _aim.scores[index]
			_gauge.draw_circle(centre, 6 + 14 * score, Color(1.0, 0.82, 0.2) if score >= 1.0 else Style.GREEN.lerp(Style.RED, 1.0 - score))
		elif index == _aim.scores.size() and pumping:
			_gauge.draw_arc(centre, 19, 0, TAU, 32, Style.CREAM, 3.0, true)
	var bar := Rect2(20, 118, width - 40, 54)
	_gauge.draw_style_box(Style.panel(Color(Style.NAVY, 0.92), 20), bar.grow(8))
	if pumping:
		var zone := bar.size.x * Aim.PERFECT
		_gauge.draw_rect(Rect2(bar.position.x + zone, bar.position.y, bar.size.x - zone, bar.size.y), Color(1.0, 0.82, 0.2, 0.9))
		var fill := bar.size.x * _aim.gauge
		_gauge.draw_rect(Rect2(bar.position, Vector2(fill, bar.size.y)), Style.GREEN.lerp(Style.ORANGE, _aim.gauge))
		_gauge.draw_rect(Rect2(bar.position.x + fill - 5, bar.position.y - 8, 10, bar.size.y + 16), Style.CREAM)
	else:
		_gauge.draw_rect(Rect2(bar.position, Vector2(bar.size.x * _aim.pressure(), bar.size.y)), Style.ORANGE)
		var perfect := _aim.power_permille >= Flight.PERFECT_POWER
		_text(font, bar.get_center() + Vector2(0, 12), ("PERFECT PRESSURE!  " if perfect else "PRESSURE %d%%   " % int(_aim.pressure() * 100)) + "ANGLE %d" % (_aim.angle_decideg / 10), 30, Style.CREAM)

func _text(font: Font, centre: Vector2, text: String, size: int, color: Color) -> void:
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var at := centre - Vector2(extent.x / 2.0, 0)
	_gauge.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 10, Color(Style.NAVY, 0.9))
	_gauge.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

## Thumb targets in the bottom corners: dive on the left, thrust on the right.
func _draw_hints() -> void:
	if not flying:
		return
	var font: Font = Style.TITLE_FONT
	var inset := Vector2(_margin.get_theme_constant("margin_left") + 110, _margin.get_theme_constant("margin_bottom") + 110)
	var spots := {"dive": Vector2(inset.x, size.y - inset.y), "thrust": Vector2(size.x - inset.x, size.y - inset.y)}
	for which: String in spots:
		var centre: Vector2 = spots[which]
		var flash: float = _hint_flash[which]
		var color: Color = Style.BLUE if which == "dive" else Style.ORANGE
		var live := which == "dive" or _thrusts > 0
		_hints.draw_circle(centre, 84 + flash * 16, Color(color, (0.3 if live else 0.12) + flash * 0.5))
		_hints.draw_arc(centre, 84 + flash * 16, 0, TAU, 48, Color(Style.CREAM, 0.75 if live else 0.3), 5.0, true)
		var word := "DIVE" if which == "dive" else "THRUST"
		var extent := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 28)
		_hints.draw_string(font, centre + Vector2(-extent.x / 2.0, 4), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(Style.CREAM, 0.95 if live else 0.4))
		if not _touch_device:
			var key := "S / RIGHT CLICK" if which == "dive" else "SPACE / CLICK"
			var key_extent := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			_hints.draw_string(font, centre + Vector2(-key_extent.x / 2.0, 32), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(Style.CREAM, 0.7))
		if which == "thrust":
			for pip in Flight.MAX_THRUSTS:
				var at := centre + Vector2((pip - (Flight.MAX_THRUSTS - 1) / 2.0) * 26.0, -112)
				if pip < _thrusts:
					_hints.draw_circle(at, 10, Style.ORANGE)
					_hints.draw_arc(at, 10, 0, TAU, 20, Style.CREAM, 2.5, true)
				elif pip < Flight.START_THRUSTS:
					_hints.draw_arc(at, 9, 0, TAU, 20, Color(Style.CREAM, 0.35), 2.0, true)
