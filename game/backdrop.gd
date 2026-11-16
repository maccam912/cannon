extends Control
## Screen-space scenery behind the world: sky, drifting clouds and a parallax
## landscape that changes biome as the distance grows.

const BIOMES := ["Grass", "Desert", "Fall", "Forest"]
const BIOME_LENGTH := 700.0   # metres per biome
const BLEND := 120.0

var textures: Array[Texture2D] = []
var ground_colors: Array[Color] = []
var sky_colors: Array[Color] = []
var clouds: Array[Texture2D] = []

## Set by the world every frame.
var camera_x := 0.0          # metres
var ground_screen_y := 600.0 # where the playfield's ground line is on screen

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for biome: String in BIOMES:
		var texture: Texture2D = load("res://assets/bg/backgroundColor%s.png" % biome)
		textures.append(texture)
		var image := texture.get_image()
		if image.is_compressed():
			image.decompress()
		ground_colors.append(image.get_pixel(8, image.get_height() - 8))
		sky_colors.append(image.get_pixel(8, 8))
	for index in [1, 2, 3, 5]:
		clouds.append(load("res://assets/bg/cloud%d.png" % index))

func biome_at(x: float) -> int:
	return int(floor(maxf(x, 0.0) / BIOME_LENGTH)) % BIOMES.size()

## Ground colour at a distance, blended across biome borders.
func ground_color(x: float) -> Color:
	var here := biome_at(x)
	var into := fmod(maxf(x, 0.0), BIOME_LENGTH)
	if into > BIOME_LENGTH - BLEND:
		var next := (here + 1) % BIOMES.size()
		return ground_colors[here].lerp(ground_colors[next], (into - (BIOME_LENGTH - BLEND)) / BLEND)
	return ground_colors[here]

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var here := biome_at(camera_x)
	var into := fmod(maxf(camera_x, 0.0), BIOME_LENGTH)
	var fade := clampf((into - (BIOME_LENGTH - BLEND)) / BLEND, 0.0, 1.0)
	var next := (here + 1) % BIOMES.size()
	draw_rect(Rect2(Vector2.ZERO, size), sky_colors[here].lerp(sky_colors[next], fade))
	# The landscape's horizon trails the real ground so climbing feels high.
	var rest := size.y * 0.8
	var horizon := rest + (ground_screen_y - rest) * 0.3
	_landscape(textures[here], horizon, 1.0)
	if fade > 0.0:
		_landscape(textures[next], horizon, fade)
	var drift := Time.get_ticks_msec() / 1000.0 * 6.0
	for index in 7:
		var texture := clouds[index % clouds.size()]
		var span := size.x + 400.0
		var x := fposmod(index * 331.0 - camera_x * (3.0 + index % 3) - drift * (1.0 + index % 2), span) - 200.0
		var y := horizon - size.y * (0.42 + 0.085 * ((index * 5) % 7))
		draw_texture(texture, Vector2(x, y), Color(1, 1, 1, 0.85))

func _landscape(texture: Texture2D, horizon: float, alpha: float) -> void:
	var scale_factor := size.y / 820.0
	var tile := Vector2(texture.get_width(), texture.get_height()) * scale_factor
	var top := horizon - tile.y * 0.635
	var offset := fposmod(-camera_x * 4.0 * scale_factor, tile.x)
	var x := offset - tile.x
	while x < size.x:
		draw_texture_rect(texture, Rect2(Vector2(x, top), tile + Vector2(1, 0)), false, Color(1, 1, 1, alpha))
		x += tile.x
	if top + tile.y < size.y:
		var ground := ground_colors[textures.find(texture)]
		draw_rect(Rect2(0, top + tile.y - 1, size.x, size.y - top - tile.y + 1), Color(ground, alpha))
