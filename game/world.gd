extends Node2D
## Draws a course and everyone flying over it. Pure presentation: it is told
## where things are and what just happened, and never decides anything.

const Course := preload("res://game/sim/course.gd")
const Flight := preload("res://game/sim/flight.gd")
const Style := preload("res://game/ui/style.gd")
const Backdrop := preload("res://game/backdrop.gd")

const PPM := 40.0   # pixels per metre at zoom 1
const HERO_SCREEN_X := 0.3
const GROUND_SCREEN_Y := 0.82
const POPUPS := {
	"spring": ["BOING!", Color(1.0, 0.75, 0.2)], "slam_spring": ["SUPER BOING!", Color(1.0, 0.5, 0.15)],
	"mud": ["SPLAT", Color(0.6, 0.42, 0.28)], "barrel": ["KABOOM!", Color(1.0, 0.4, 0.2)],
	"cactus": ["OUCH!", Color(0.5, 0.9, 0.45)], "ring": ["WHOOSH!", Color(1.0, 0.72, 0.25)],
	"wingman": ["BONK!", Color(1.0, 0.9, 0.4)], "fuel": ["+1 THRUST", Color(0.5, 0.85, 1.0)],
	"storm": ["ZAP!", Color(1.0, 0.95, 0.4)],
}
## Foreground scenery is limited to things that cannot be mistaken for the
## course: no trees or cacti, the backdrop already has those.
const DECOR := [
	["house1", "fence", "houseSmall1", "bush1"],
	["pyramid", "fence", "pyramid"],
	["tower", "fence", "bushOrange1", "house1"],
	["houseSmall1", "fence", "bush2", "tower"],
]

var course: Course
var backdrop: Backdrop
var camera: Camera2D
var cannon: Node2D
var hero: Node2D
var hero_sprite: Sprite2D
var flame: Sprite2D
var trail: Line2D
var shadow: Sprite2D

var _layer: CanvasLayer
var _decor_root: Node2D
var _items_root: Node2D
var _ghost_root: Node2D
var _fx_root: Node2D
var _items: Dictionary = {}     # item id -> Node2D
var _chunks: Dictionary = {}    # chunk index -> Array[Node]
var _ghosts: Dictionary = {}    # player id -> Node2D
var _textures: Dictionary = {}
var _focus := Vector2(0.0, Flight.MUZZLE_Y)   # metres
var _speed := 0.0
var _zoom := 1.0
var _shake := 0.0
var _spin := 0.0
var _flame_time := 0.0
var _coin_streak := 0
var _coin_clock := 0.0
var _barrel_angle := 45.0
var _recoil := 0.0
var _clock := 0.0
## Menu demo flights keep their effects but stay silent.
var muted := false

func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = -10
	add_child(_layer)
	backdrop = Backdrop.new()
	_layer.add_child(backdrop)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	_decor_root = _group(-3)
	var ground := Node2D.new()
	ground.z_index = -2
	ground.draw.connect(_draw_ground.bind(ground))
	add_child(ground)
	set_meta("ground", ground)
	_items_root = _group(0)
	cannon = Node2D.new()
	cannon.z_index = 3
	cannon.draw.connect(_draw_cannon)
	add_child(cannon)
	_ghost_root = _group(4)
	trail = Line2D.new()
	trail.z_index = 5
	trail.width = 22.0
	trail.joint_mode = Line2D.LINE_JOINT_ROUND
	trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.0))
	curve.add_point(Vector2(1, 1.0))
	trail.width_curve = curve
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.0))
	gradient.set_color(1, Color(1, 1, 1, 0.55))
	trail.gradient = gradient
	add_child(trail)
	shadow = Sprite2D.new()
	shadow.texture = _texture("splat")
	shadow.modulate = Color(0, 0, 0, 0.25)
	shadow.z_index = 1
	add_child(shadow)
	hero = Node2D.new()
	hero.z_index = 6
	add_child(hero)
	flame = Sprite2D.new()
	flame.texture = _texture("flame")
	flame.position = Vector2(-30, 22)
	flame.rotation_degrees = 60.0
	flame.visible = false
	hero.add_child(flame)
	hero_sprite = Sprite2D.new()
	hero.add_child(hero_sprite)
	_fx_root = _group(8)
	setup(1, 0)

func _group(z: int) -> Node2D:
	var node := Node2D.new()
	node.z_index = z
	add_child(node)
	return node

func _texture(sprite: String) -> Texture2D:
	if not _textures.has(sprite):
		var folder := "bg" if ResourceLoader.exists("res://assets/bg/%s.png" % sprite) else "sprites"
		_textures[sprite] = load("res://assets/%s/%s.png" % [folder, sprite])
	return _textures[sprite]

## Fresh course with the local cannonaut loaded in the cannon.
func setup(course_seed: int, slot: int, levels: Variant = null) -> void:
	course = Flight.make_course(course_seed, levels)
	for nodes: Array in _chunks.values():
		for node: Node in nodes:
			node.queue_free()
	_chunks.clear()
	_items.clear()
	for node: Node in _fx_root.get_children():
		node.queue_free()
	set_ghosts([])
	hero_sprite.texture = Style.alien(slot)
	hero_sprite.scale = Vector2.ONE * (Flight.RADIUS * 2.0 * PPM / hero_sprite.texture.get_width()) * 1.45
	hero.visible = false
	hero.scale = Vector2.ONE
	shadow.visible = false
	flame.visible = false
	trail.clear_points()
	_focus = Vector2(0.0, Flight.MUZZLE_Y)
	_speed = 0.0
	_spin = 0.0
	_coin_streak = 0
	_shake = 0.0
	_recoil = 0.0
	_snap_camera()

## Barrel angle in degrees and how hard it is pumped (0..1), while aiming.
func set_aim(angle_degrees: float, pressure: float) -> void:
	_barrel_angle = angle_degrees
	cannon.set_meta("pressure", pressure)
	cannon.queue_redraw()

func fire() -> void:
	_recoil = 1.0
	shake(16.0)
	hero.visible = true
	shadow.visible = true
	var muzzle := to_pixels(0.3, Flight.MUZZLE_Y + 1.0)
	_burst(muzzle, Color(1, 0.85, 0.5), 26, 520.0, 0.5)
	_burst(muzzle, Color(0.9, 0.9, 0.9, 0.8), 18, 220.0, 0.9, _texture("smoke"))
	_flash(muzzle, Color(1.0, 0.9, 0.6), 190.0)

static func to_pixels(x: float, y: float) -> Vector2:
	return Vector2(x * PPM, -y * PPM)

## Where the local cannonaut is this frame (metres, y = underside height).
func show_hero(x: float, y: float, vx: float, vy: float, rolling: bool, diving: bool, delta: float) -> void:
	_focus = Vector2(x, y)
	_speed = vx
	hero.position = to_pixels(x, y + Flight.RADIUS)
	_spin += vx * delta / Flight.RADIUS * (1.0 if rolling or y <= 0.0 else 0.35)
	hero_sprite.rotation = _spin
	var stretch := clampf(absf(vy) / 90.0, 0.0, 0.28) if not rolling else 0.0
	if diving:
		stretch = 0.3
	hero_sprite.scale = hero_sprite.scale.lerp(_hero_scale() * Vector2(1.0 - stretch * 0.5, 1.0 + stretch), 0.4)
	shadow.position = to_pixels(x, 0.0) + Vector2(0, 5)
	var closeness := clampf(1.0 - y / 20.0, 0.25, 1.0)
	shadow.scale = Vector2(0.34, 0.07) * closeness
	shadow.modulate.a = 0.3 * closeness
	trail.add_point(hero.position)
	while trail.get_point_count() > 26:
		trail.remove_point(0)

func _hero_scale() -> Vector2:
	return Vector2.ONE * (Flight.RADIUS * 2.0 * PPM / hero_sprite.texture.get_width()) * 1.45

## Other players this round: [{id, slot, name, x, y, state}].
func set_ghosts(rows: Array) -> void:
	var seen: Dictionary = {}
	for row: Dictionary in rows:
		seen[row.id] = true
		if not _ghosts.has(row.id):
			var node := Node2D.new()
			var sprite := Sprite2D.new()
			sprite.texture = Style.alien(row.slot)
			sprite.scale = Vector2.ONE * (Flight.RADIUS * 2.0 * PPM / sprite.texture.get_width()) * 1.3
			sprite.modulate.a = 0.75
			node.add_child(sprite)
			var tag := Style.label(row.name, 22, Style.seat_color(row.slot), true)
			Style.outline(tag, 6)
			tag.position = Vector2(-100, -62)
			tag.custom_minimum_size.x = 200
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			node.add_child(tag)
			node.position = to_pixels(row.x, row.y + Flight.RADIUS)
			node.set_meta("sprite", sprite)
			_ghost_root.add_child(node)
			_ghosts[row.id] = node
		var ghost: Node2D = _ghosts[row.id]
		ghost.set_meta("target", to_pixels(row.x, row.y + Flight.RADIUS))
		ghost.visible = row.state != 0
	for id: int in _ghosts.keys():
		if not seen.has(id):
			_ghosts[id].queue_free()
			_ghosts.erase(id)

## Party spectating: look at someone else once the local flight is over.
func watch(x: float, y: float, vx: float) -> void:
	_focus = Vector2(x, y)
	_speed = vx

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

## Reacts to one Flight event with sound, particles and pop-up text.
func handle_event(event: Dictionary) -> void:
	var at := to_pixels(event.x, event.y + Flight.RADIUS)
	var kind: String = event.kind
	var node: Node2D = _items.get(event.id)
	if POPUPS.has(kind):
		_popup(at + Vector2(0, -50), POPUPS[kind][0], POPUPS[kind][1])
	match kind:
		"bounce":
			var strength := clampf(event.strength / 30.0, 0.15, 1.0)
			_sound("bounce1" if randf() < 0.5 else "bounce2", 1.25 - strength * 0.45, -10.0 + strength * 10.0)
			_burst(at + Vector2(0, 20), Color(backdrop.ground_color(event.x).darkened(0.1), 0.9), int(6 + strength * 12), 150.0 + strength * 180.0, 0.5)
			_squash()
			if strength > 0.5:
				shake(strength * 7.0)
		"spring", "slam_spring":
			_sound("spring", 1.3 if kind == "slam_spring" else 1.0)
			shake(10.0 if kind == "slam_spring" else 5.0)
			_squash()
			if node != null:
				var sprite: Sprite2D = node.get_meta("sprite")
				sprite.texture = _texture("spring_out")
				sprite.offset.y = -sprite.texture.get_height() / 2.0
				_burst(at + Vector2(0, 16), Color(1.0, 0.8, 0.3), 14, 320.0, 0.45)
		"mud":
			_sound("mud")
			_burst(at + Vector2(0, 20), Color(0.42, 0.29, 0.18), 22, 260.0, 0.7)
			_squash()
		"barrel":
			_sound("boom")
			shake(22.0)
			_flash(at, Color(1.0, 0.75, 0.3), 260.0)
			_burst(at, Color(1.0, 0.55, 0.15), 34, 620.0, 0.6)
			_burst(at, Color(0.3, 0.3, 0.32, 0.8), 16, 240.0, 1.0, _texture("smoke"))
			if node != null:
				node.visible = false
		"cactus":
			_sound("thud")
			shake(9.0)
			_burst(at, Color(0.35, 0.75, 0.4), 16, 300.0, 0.6)
			if node != null:
				var tween := node.create_tween().set_parallel()
				tween.tween_property(node, "rotation_degrees", 80.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tween.tween_property(node, "modulate:a", 0.45, 0.35)
		"ring":
			_sound("ring")
			_burst(at, Color(1.0, 0.8, 0.35), 20, 420.0, 0.5)
			if node != null:
				var tween := node.create_tween().set_parallel()
				tween.tween_property(node, "scale", node.scale * 1.8, 0.3)
				tween.tween_property(node, "modulate:a", 0.0, 0.3)
		"wingman":
			_sound("bell", 1.4, -4.0)
			shake(5.0)
			_burst(at, Color(1, 1, 1), 12, 300.0, 0.5)
			_squash()
			if node != null:
				node.set_meta("fleeing", true)
		"fuel":
			_sound("refill")
			_burst(at, Color(0.5, 0.85, 1.0), 14, 260.0, 0.5)
			if node != null:
				node.visible = false
		"storm":
			_sound("zap")
			shake(12.0)
			_flash(at, Color(1.0, 1.0, 0.6), 200.0)
			var bolt := Sprite2D.new()
			bolt.texture = _texture("lighting_yellow")
			bolt.position = at + Vector2(0, 40)
			bolt.scale = Vector2.ONE * 1.4
			_fx_root.add_child(bolt)
			var tween := bolt.create_tween()
			tween.tween_property(bolt, "modulate:a", 0.0, 0.35)
			tween.tween_callback(bolt.queue_free)
		"coin":
			_coin_streak = _coin_streak + 1 if _coin_clock > 0.0 else 0
			_coin_clock = 0.9
			_sound("coin", 1.0 + minf(_coin_streak, 10) * 0.07, -6.0)
			_burst(at, Color(1.0, 0.85, 0.25), 6, 200.0, 0.35)
			if node != null:
				node.visible = false
		"thrust":
			_sound("thrust", 1.0, -3.0)
			_flame_time = 0.35
			_burst(at + Vector2(-20, 20), Color(1.0, 0.6, 0.2), 14, 300.0, 0.4)
			_burst(at + Vector2(-20, 20), Color(0.95, 0.95, 0.95, 0.7), 8, 120.0, 0.8, _texture("smoke"))
		"dive":
			_sound("dive", 1.0, -6.0)
		"stop":
			_sound("thud", 0.8, -4.0)

func _sound(sound: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not muted:
		Sfx.play(sound, pitch, volume_db)

func _squash() -> void:
	hero_sprite.scale = _hero_scale() * Vector2(1.35, 0.65)

func popup(x: float, y: float, text: String, color: Color) -> void:
	_popup(to_pixels(x, y), text, color)

func _popup(at: Vector2, text: String, color: Color) -> void:
	var label := Style.label(text, 34, color, true)
	Style.outline(label, 10)
	label.custom_minimum_size = Vector2(400, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.pivot_offset = Vector2(200, 20)
	label.position = at - Vector2(200, 20)
	label.scale = Vector2.ONE * 0.4 / _zoom
	label.rotation_degrees = randf_range(-8.0, 8.0)
	_fx_root.add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector2.ONE / _zoom, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "position:y", label.position.y - 70.0 / _zoom, 0.9)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tween.tween_callback(label.queue_free)

func _burst(at: Vector2, color: Color, amount: int, speed: float, lifetime: float, texture: Texture2D = null) -> void:
	var particles := CPUParticles2D.new()
	particles.position = at
	particles.amount = amount
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.lifetime = lifetime
	particles.direction = Vector2(0, -1)
	particles.spread = 180.0
	particles.gravity = Vector2(0, 500)
	particles.initial_velocity_min = speed * 0.4
	particles.initial_velocity_max = speed
	particles.color = color
	if texture != null:
		particles.texture = texture
		particles.scale_amount_min = 0.5
		particles.scale_amount_max = 1.1
		particles.gravity = Vector2(0, -60)
	else:
		particles.scale_amount_min = 5.0
		particles.scale_amount_max = 11.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = fade
	particles.emitting = true
	_fx_root.add_child(particles)
	get_tree().create_timer(lifetime + 0.3).timeout.connect(particles.queue_free)

func _flash(at: Vector2, color: Color, radius: float) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = _texture("explosion1")
	sprite.position = at
	sprite.modulate = color
	sprite.scale = Vector2.ONE * radius / 128.0
	_fx_root.add_child(sprite)
	var tween := sprite.create_tween().set_parallel()
	tween.tween_property(sprite, "scale", sprite.scale * 2.4, 0.25)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.25)
	tween.chain().tween_callback(sprite.queue_free)

func _process(delta: float) -> void:
	_clock += delta
	_coin_clock = maxf(_coin_clock - delta, 0.0)
	_flame_time = maxf(_flame_time - delta, 0.0)
	flame.visible = _flame_time > 0.0
	flame.scale = Vector2.ONE * (1.0 + _flame_time * 2.0)
	if _recoil > 0.0:
		_recoil = maxf(_recoil - delta * 3.0, 0.0)
		cannon.queue_redraw()
	_update_camera(delta)
	_load_chunks()
	_animate_items(delta)
	for ghost: Node2D in _ghosts.values():
		var target: Vector2 = ghost.get_meta("target")
		var before := ghost.position
		ghost.position = ghost.position.lerp(target, clampf(delta * 10.0, 0.0, 1.0))
		(ghost.get_meta("sprite") as Sprite2D).rotation += (ghost.position.x - before.x) / (Flight.RADIUS * PPM) * 0.5
	(get_meta("ground") as Node2D).queue_redraw()

func _target_zoom() -> float:
	var view := get_viewport_rect().size
	var tall := clampf(_focus.y * 1.1 + 12.0 + _speed * 0.12, 16.0, 52.0)
	return view.y / (tall * PPM)

func _snap_camera() -> void:
	_zoom = _target_zoom()
	_update_camera(0.0)

func _update_camera(delta: float) -> void:
	var view := get_viewport_rect().size
	_zoom = lerpf(_zoom, _target_zoom(), clampf(delta * 2.5, 0.0, 1.0))
	camera.zoom = Vector2.ONE * _zoom
	var center := Vector2(_focus.x * PPM + (0.5 - HERO_SCREEN_X) * view.x / _zoom, -(GROUND_SCREEN_Y - 0.5) * view.y / _zoom)
	center.y = minf(center.y, -(_focus.y + Flight.RADIUS) * PPM + 0.3 * view.y / _zoom)
	_shake = maxf(_shake - delta * 40.0, 0.0)
	camera.position = center + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake / _zoom
	backdrop.camera_x = center.x / PPM
	backdrop.ground_screen_y = (0.0 - center.y) * _zoom + view.y / 2.0

## Visible span in metres, with a margin so nothing pops in.
func _view_range() -> Vector2:
	var half := get_viewport_rect().size.x / _zoom / 2.0 / PPM
	var middle := camera.position.x / PPM
	return Vector2(middle - half - 12.0, middle + half + 12.0)

func _load_chunks() -> void:
	var span := _view_range()
	var first := maxi(int(floor(span.x / Course.CHUNK)), 0)
	var last := int(floor(span.y / Course.CHUNK))
	for index: int in _chunks.keys():
		if index < first - 1 or index > last + 1:
			for node: Node in _chunks[index]:
				if node.has_meta("id"):
					_items.erase(node.get_meta("id"))
				node.queue_free()
			_chunks.erase(index)
	for index in range(first, last + 1):
		if not _chunks.has(index):
			_chunks[index] = _build_chunk(index)

func _build_chunk(index: int) -> Array:
	var nodes: Array = []
	# Scenery uses its own generator so it can never disturb the course.
	var random := RandomNumberGenerator.new()
	random.seed = index * 7919 + 17
	var biome: Array = DECOR[backdrop.biome_at(index * Course.CHUNK)]
	for _count in 1 + random.randi() % 2:
		var sprite := Sprite2D.new()
		sprite.texture = _texture(biome[random.randi() % biome.size()])
		var size := random.randf_range(0.8, 1.25)
		sprite.scale = Vector2.ONE * size
		sprite.position = Vector2((index * Course.CHUNK + random.randf_range(0, Course.CHUNK)) * PPM, -sprite.texture.get_height() * size / 2.0 + 4.0)
		sprite.modulate = Color(0.9, 0.95, 0.95, 1.0)
		_decor_root.add_child(sprite)
		nodes.append(sprite)
	for item: Dictionary in course.chunk(index):
		var node := _build_item(item)
		node.set_meta("id", item.id)
		node.set_meta("kind", item.kind)
		node.set_meta("home", node.position)
		_items_root.add_child(node)
		_items[item.id] = node
		nodes.append(node)
	return nodes

func _build_item(item: Dictionary) -> Node2D:
	var node := Node2D.new()
	var sprite := Sprite2D.new()
	node.add_child(sprite)
	node.set_meta("sprite", sprite)
	node.position = to_pixels(item.x, item.y)
	var wide := 0.0   # target width in metres
	match item.kind:
		Course.Kind.SPRING:
			sprite.texture = _texture("spring")
			wide = 3.2
			sprite.offset.y = -sprite.texture.get_height() / 2.0
		Course.Kind.MUD:
			sprite.texture = _texture("splat")
			sprite.modulate = Color(0.36, 0.25, 0.16)
			sprite.scale = Vector2(4.8 * PPM / 256.0, 0.2)
			sprite.position.y = 6.0
		Course.Kind.BARREL:
			sprite.texture = _texture("barrel_red")
			wide = 1.55
			node.position = to_pixels(item.x, 0.0)
			sprite.offset.y = -sprite.texture.get_height() / 2.0
		Course.Kind.CACTUS:
			sprite.texture = _texture("cactus")
			wide = 1.9
			node.position = to_pixels(item.x, 0.0)
			sprite.offset.y = -sprite.texture.get_height() / 2.0
		Course.Kind.RING:
			sprite.texture = _texture("portal_orange")
			sprite.rotation_degrees = 90.0
			wide = 3.6
		Course.Kind.WINGMAN:
			sprite.texture = _texture("wingman1")
			wide = 2.8
		Course.Kind.FUEL:
			sprite.texture = _texture("powerup_jetpack")
			wide = 1.9
		Course.Kind.STORM:
			sprite.texture = _texture("cloud")
			sprite.modulate = Color(0.42, 0.44, 0.55)
			wide = 4.4
		Course.Kind.COIN:
			sprite.texture = _texture("gold_1")
			wide = 1.3
	if wide > 0.0:
		sprite.scale = Vector2.ONE * wide * PPM / sprite.texture.get_width()
	return node

func _animate_items(delta: float) -> void:
	for node: Node2D in _items.values():
		if not node.visible:
			continue
		var home: Vector2 = node.get_meta("home")
		var phase := _clock * 3.0 + home.x * 0.01
		match int(node.get_meta("kind")):
			Course.Kind.WINGMAN:
				(node.get_meta("sprite") as Sprite2D).texture = _texture("wingman%d" % (1 + int(_clock * 12.0 + home.x) % 5))
				if node.has_meta("fleeing"):
					node.position += Vector2(120, -520) * delta
					node.modulate.a = maxf(node.modulate.a - delta * 1.5, 0.0)
				else:
					node.position.y = home.y + sin(phase) * 8.0
			Course.Kind.COIN:
				(node.get_meta("sprite") as Sprite2D).texture = _texture("gold_%d" % (1 + int(_clock * 9.0 + home.x * 0.05) % 4))
			Course.Kind.FUEL:
				node.position.y = home.y + sin(phase) * 7.0
				node.rotation = sin(phase * 0.7) * 0.15
			Course.Kind.RING:
				if node.modulate.a >= 1.0:
					node.scale = Vector2.ONE * (1.0 + sin(phase * 1.4) * 0.05)
			Course.Kind.STORM:
				node.position.x = home.x + sin(phase * 0.5) * 6.0

func _draw_ground(ground: Node2D) -> void:
	var span := _view_range()
	var font: Font = Style.TITLE_FONT
	# Soil in strips so it follows the biome colour underneath it.
	var step := 16.0
	var x := floorf(span.x / step) * step
	while x < span.y:
		var color := backdrop.ground_color(x + step / 2.0)
		ground.draw_rect(Rect2(x * PPM, 0, step * PPM + 1, 4000), color.darkened(0.3))
		ground.draw_rect(Rect2(x * PPM, 0, step * PPM + 1, 14), color.lightened(0.18))
		ground.draw_rect(Rect2(x * PPM, 14, step * PPM + 1, 10), color.darkened(0.12))
		x += step
	# A marker post every 100 m and a bigger one every 500 m.
	var mark := maxf(ceilf(span.x / 100.0) * 100.0, 100.0)
	while mark < span.y:
		var big := int(mark) % 500 == 0
		var at := Vector2(mark * PPM, 0)
		var height := 170.0 if big else 110.0
		ground.draw_rect(Rect2(at.x - 4, -height, 8, height), Color(0.45, 0.32, 0.22))
		var board := Rect2(at.x - (86 if big else 62), -height - (62 if big else 46), 172 if big else 124, 62 if big else 46)
		ground.draw_rect(board, Color(1.0, 0.95, 0.85))
		ground.draw_rect(board, Color(0.45, 0.32, 0.22), false, 4.0)
		var size := 40 if big else 30
		var baseline := board.get_center().y + (font.get_ascent(size) - font.get_descent(size)) / 2.0
		ground.draw_string(font, Vector2(board.position.x, baseline), "%d" % int(mark),
				HORIZONTAL_ALIGNMENT_CENTER, board.size.x, size, Color(0.25, 0.18, 0.14))
		mark += 100.0

func _draw_cannon() -> void:
	var pivot := to_pixels(-1.5, 1.5)
	var pressure: float = cannon.get_meta("pressure", 0.0)
	# Carriage and wheel.
	cannon.draw_colored_polygon(PackedVector2Array([pivot + Vector2(-70, 60), pivot + Vector2(70, 60), pivot + Vector2(34, -6), pivot + Vector2(-34, -6)]), Color(0.42, 0.28, 0.2))
	cannon.draw_set_transform(pivot, -deg_to_rad(_barrel_angle), Vector2.ONE)
	var kick := -_recoil * 26.0
	var swell := 1.0 + pressure * 0.12
	var barrel := Rect2(-46 + kick, -30 * swell, 190, 60 * swell)
	cannon.draw_rect(barrel, Color(0.16, 0.18, 0.26))
	cannon.draw_circle(Vector2(-46 + kick, 0), 30 * swell, Color(0.16, 0.18, 0.26))
	cannon.draw_rect(Rect2(124 + kick, -36 * swell, 22, 72 * swell), Color(0.3, 0.33, 0.44))
	cannon.draw_rect(Rect2(20 + kick, -32 * swell, 14, 64 * swell), Color(0.3, 0.33, 0.44))
	cannon.draw_rect(Rect2(-46 + kick, -30 * swell, 190, 12), Color(1, 1, 1, 0.12))
	# The barrel glows as the pressure builds.
	cannon.draw_rect(barrel, Color(1.0, 0.35, 0.1, pressure * 0.45))
	cannon.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	cannon.draw_circle(pivot + Vector2(0, 20), 40, Color(0.3, 0.2, 0.14))
	cannon.draw_circle(pivot + Vector2(0, 20), 30, Color(0.55, 0.38, 0.26))
	cannon.draw_circle(pivot + Vector2(0, 20), 9, Color(0.3, 0.2, 0.14))
