extends RefCounted
## Shared look: fonts, chunky touch-sized buttons, panels, player colours.

const TITLE_FONT := preload("res://assets/fonts/kenney_bold.ttf")
const BODY_FONT := preload("res://assets/fonts/kenney_bold.ttf")

const NAVY := Color(0.07, 0.11, 0.2)
const INK := Color(0.1, 0.14, 0.26)
const CREAM := Color(1.0, 0.97, 0.9)
const ORANGE := Color(1.0, 0.58, 0.12)
const BLUE := Color(0.2, 0.55, 0.98)
const GREEN := Color(0.25, 0.78, 0.42)
const RED := Color(0.93, 0.33, 0.33)
const SLATE := Color(0.27, 0.33, 0.47)

## One look per seat: five round cannonauts, then three square ones.
const ALIENS := ["alien_green", "alien_blue", "alien_pink", "alien_yellow", "alien_beige",
		"alien_green_square", "alien_blue_square", "alien_pink_square"]
const SEAT_COLORS := [Color(0.42, 0.82, 0.5), Color(0.38, 0.68, 0.95), Color(0.96, 0.5, 0.7), Color(0.98, 0.8, 0.25),
		Color(0.87, 0.75, 0.58), Color(0.3, 0.66, 0.4), Color(0.28, 0.5, 0.8), Color(0.8, 0.38, 0.58)]

static func alien(slot: int) -> Texture2D:
	return load("res://assets/sprites/%s.png" % ALIENS[clampi(slot, 0, ALIENS.size() - 1)])

static func seat_color(slot: int) -> Color:
	return SEAT_COLORS[clampi(slot, 0, SEAT_COLORS.size() - 1)]

static func meters(distance_cm: int) -> String:
	return "%d m" % (distance_cm / 100) if distance_cm >= 100000 else "%.1f m" % (distance_cm / 100.0)

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = BODY_FONT
	result.default_font_size = 28
	result.set_color("font_color", "Label", CREAM)
	result.set_stylebox("normal", "LineEdit", _box(Color(0.03, 0.05, 0.1, 0.9), 14, 0, 18, 12))
	result.set_stylebox("focus", "LineEdit", _box(Color(0.03, 0.05, 0.1, 0.9), 14, 0, 18, 12, ORANGE, 3))
	result.set_color("font_color", "LineEdit", CREAM)
	result.set_color("font_placeholder_color", "LineEdit", Color(CREAM, 0.4))
	result.set_color("caret_color", "LineEdit", ORANGE)
	result.set_stylebox("panel", "PanelContainer", _box(Color(NAVY, 0.9), 24, 0, 28, 22))
	return result

## A big rounded button with a darker lip so it reads as pressable.
static func button(text: String, color: Color = ORANGE, font_size: int = 30) -> Button:
	var node := Button.new()
	node.text = text
	node.focus_mode = Control.FOCUS_NONE
	node.custom_minimum_size = Vector2(0, 72)
	node.add_theme_font_override("font", TITLE_FONT)
	node.add_theme_font_size_override("font_size", font_size)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(state, CREAM if color.get_luminance() < 0.6 else INK)
	node.add_theme_color_override("font_disabled_color", Color(CREAM, 0.45))
	node.add_theme_stylebox_override("normal", _box(color, 18, 7, 28, 12))
	node.add_theme_stylebox_override("hover", _box(color.lightened(0.08), 18, 7, 28, 12))
	node.add_theme_stylebox_override("pressed", _box(color.darkened(0.12), 18, 2, 28, 12, Color.TRANSPARENT, 0, 5))
	node.add_theme_stylebox_override("disabled", _box(SLATE.darkened(0.2), 18, 7, 28, 12))
	node.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	node.pressed.connect(func() -> void: Sfx.play("click"))
	return node

static func label(text: String, size: int = 28, color: Color = CREAM, title: bool = false) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	if title:
		node.add_theme_font_override("font", TITLE_FONT)
	return node

## Adds a dark outline so text stays readable over the scenery.
static func outline(node: Control, size: int = 8) -> void:
	node.add_theme_color_override("font_outline_color", Color(NAVY, 0.9))
	node.add_theme_constant_override("outline_size", size)

static func panel(color: Color = Color(NAVY, 0.9), radius: int = 24) -> StyleBoxFlat:
	return _box(color, radius, 0, 28, 22)

static func _box(color: Color, radius: int, lip: int, pad_x: int, pad_y: int, border: Color = Color.TRANSPARENT, border_width: int = 0, drop: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y + drop
	box.content_margin_bottom = pad_y + lip - drop
	box.anti_aliasing = true
	if lip > 0:
		box.border_width_bottom = lip
		box.border_color = color.darkened(0.3)
	if border_width > 0:
		box.set_border_width_all(border_width)
		box.border_color = border
	if drop > 0:
		box.expand_margin_top = -float(drop)
	return box
