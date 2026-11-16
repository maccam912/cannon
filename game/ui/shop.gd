extends Control
## Upgrade shop: spend stars on permanent boosts to your solo cannon.

signal back_pressed
signal launch_pressed

const Style := preload("res://game/ui/style.gd")
const Upgrades := preload("res://game/sim/upgrades.gd")

const ACCENTS := {
	"powder": Color(1.0, 0.58, 0.12), "rubber": Color(0.96, 0.5, 0.7), "springs": Color(0.98, 0.8, 0.25),
	"farm": Color(0.42, 0.82, 0.5), "thrusters": Color(0.38, 0.68, 0.95), "slipstream": Color(0.6, 0.9, 0.95),
	"luck": Color(0.75, 0.6, 1.0),
}

var _stars: Label
var _grid: GridContainer
var _coin: Texture2D = preload("res://assets/sprites/gold_1.png")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Style.theme()
	var shade := ColorRect.new()
	shade.color = Color(Style.NAVY, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	var title := Style.label("UPGRADES", 38, Style.ORANGE, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_coin_icon(38))
	_stars = Style.label("0", 38, Color(1.0, 0.85, 0.3), true)
	header.add_child(_stars)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	column.add_child(_grid)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	column.add_child(footer)
	var back := Style.button("BACK", Style.SLATE, 26)
	back.custom_minimum_size = Vector2(200, 60)
	back.pressed.connect(func() -> void: back_pressed.emit())
	footer.add_child(back)
	var hint := Style.label("Stars: 1 per 10 m flown, 3 per coin, 10 for perfect pressure. Party rounds pay too.", 17, Color(Style.CREAM, 0.75))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 300
	footer.add_child(hint)
	var launch := Style.button("LAUNCH", Style.ORANGE, 26)
	launch.custom_minimum_size = Vector2(260, 60)
	launch.pressed.connect(func() -> void: launch_pressed.emit())
	footer.add_child(launch)
	refresh()

func _coin_icon(size: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = _coin
	icon.custom_minimum_size = Vector2(size, size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon

func refresh() -> void:
	_stars.text = str(Save.stars)
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for id: String in Upgrades.IDS:
		_grid.add_child(_card(id))
	_grid.add_child(_stats())

func _card(id: String) -> Control:
	var info: Dictionary = Upgrades.INFO[id]
	var level: int = Save.levels[id]
	var top := Upgrades.max_level(id)
	var accent: Color = ACCENTS[id]
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_box(Color(Style.INK, 0.96)))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)
	var heading := Style.label(str(info.name).to_upper(), 22, accent, true)
	heading.clip_text = true
	box.add_child(heading)
	# One pip per level.
	var pips := Control.new()
	pips.custom_minimum_size = Vector2(0, 12)
	pips.draw.connect(func() -> void:
		var gap := 4.0
		var width := (pips.size.x - gap * (top - 1)) / top
		for index in top:
			pips.draw_rect(Rect2(index * (width + gap), 0, width, 10), accent if index < level else Color(1, 1, 1, 0.12)))
	box.add_child(pips)
	var now := Style.label(Upgrades.effect(id, level), 18)
	now.clip_text = true
	box.add_child(now)
	var blurb := Style.label(info.blurb, 15, Color(Style.CREAM, 0.65))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.x = 120
	blurb.clip_text = true
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(blurb)
	if level >= top:
		var done := Style.button("MAXED", Style.SLATE, 22)
		done.custom_minimum_size.y = 52
		done.disabled = true
		box.add_child(done)
		return card
	var price := Save.price(id)
	var buy := Style.button("%d" % price, Style.GREEN if Save.can_buy(id) else Style.SLATE, 24)
	buy.custom_minimum_size.y = 52
	buy.icon = _coin
	buy.expand_icon = true
	buy.add_theme_constant_override("icon_max_width", 28)
	buy.disabled = not Save.can_buy(id)
	buy.tooltip_text = "Next: " + Upgrades.effect(id, level + 1)
	buy.pressed.connect(func() -> void:
		if Save.buy(id):
			Sfx.play("refill")
			refresh())
	box.add_child(buy)
	return card

func _card_box(color: Color) -> StyleBoxFlat:
	var box := Style.panel(color, 16)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 12
	return box

func _stats() -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_box(Color(1, 1, 1, 0.06)))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var heading := Style.label("YOUR CANNON", 22, Color(Style.CREAM, 0.8), true)
	heading.clip_text = true
	box.add_child(heading)
	for line: Array in [["Best", Style.meters(Save.best_cm)], ["Launches", str(Save.launches)], ["Stars earned", str(Save.earned)]]:
		var row := HBoxContainer.new()
		var name_label := Style.label(line[0], 16, Color(Style.CREAM, 0.65))
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(Style.label(line[1], 18))
		box.add_child(row)
	return card
