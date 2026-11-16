extends RefCounted
## Deterministic launch simulation: one cannonaut, one course.
##
## Fixed 60 Hz ticks, scalar doubles, + - * / sqrt and integer RNG only (no
## Vector2, no libm trig), so any device replays exactly the same flight from
## (seed, angle, power, inputs). The party host relies on that to re-run and
## verify what clients claim.

const Course := preload("res://game/sim/course.gd")

const TICK := 1.0 / 60.0
const GRAVITY := 22.0
const DRAG := 0.035
const RADIUS := 0.6
const MUZZLE_Y := 2.4
const MAX_TICKS := 60 * 150
const MIN_ANGLE := 200   # tenths of a degree
const MAX_ANGLE := 700
const MAX_POWER := 1000  # per mille
const PERFECT_POWER := 940
const START_THRUSTS := 3
const MAX_THRUSTS := 5
const MAX_INPUTS := 200

const IN_THRUST := 1
const IN_DIVE := 2

const BASE_SPEED := 22.0
const POWER_SPEED := 30.0
const RESTITUTION := 0.56
const GROUND_GRIP := 0.87
const ROLL_FRICTION := 5.0

var course: Course
var x := 0.0
var y := MUZZLE_Y          # height of the cannonaut's underside above ground
var vx := 0.0
var vy := 0.0
var tick := 0
var thrusts := START_THRUSTS
var coins := 0
var diving := false
var rolling := false
var done := false
var perfect := false
var max_height := 0.0
var consumed: Dictionary = {}
## Presentation drains this: [{kind, x, y, id, strength}]. Never read by rules.
var events: Array = []

var _dive_impact := 0.0
var _thrust_cooldown := 0
var _dive_cooldown := 0

func _init(course_seed: int = 1) -> void:
	course = Course.new(course_seed)

func launch(angle_decideg: int, power_permille: int) -> void:
	angle_decideg = clampi(angle_decideg, MIN_ANGLE, MAX_ANGLE)
	power_permille = clampi(power_permille, 0, MAX_POWER)
	perfect = power_permille >= PERFECT_POWER
	var speed := BASE_SPEED + POWER_SPEED * power_permille / 1000.0
	if perfect:
		speed *= 1.08
	var radians := angle_decideg * (PI / 1800.0)
	vx = speed * cosine(radians)
	vy = speed * sine(radians)
	x = 0.0
	y = MUZZLE_Y

## Applies one tick. Returns the input bits that actually took effect, which
## is what gets logged and sent to the host.
func step(input: int = 0) -> int:
	if done:
		return 0
	var applied := 0
	if _thrust_cooldown > 0:
		_thrust_cooldown -= 1
	if _dive_cooldown > 0:
		_dive_cooldown -= 1
	if input & IN_THRUST and thrusts > 0 and _thrust_cooldown == 0:
		thrusts -= 1
		_thrust_cooldown = 18
		vx += 6.0
		vy = maxf(vy, 0.0) * 0.5 + 11.5
		_lift_off()
		applied |= IN_THRUST
		_emit("thrust")
	elif input & IN_DIVE and not rolling and not diving and y > 1.2 and _dive_cooldown == 0:
		# A dive only gets you down sooner: the landing uses the speed you
		# would have hit with anyway, so it steers but never adds energy.
		diving = true
		_dive_cooldown = 30
		_dive_impact = sqrt(vy * vy + 2.0 * GRAVITY * y)
		vy = minf(vy - 10.0, -22.0)
		applied |= IN_DIVE
		_emit("dive")
	var from_x := x
	var from_y := y
	if rolling:
		vx -= ROLL_FRICTION * TICK
		if vx <= 0.4:
			vx = 0.0
			_finish()
			return applied
		x += vx * TICK
		_touch_ground_pad(x, 0.0, false)
	else:
		vy -= GRAVITY * TICK
		vx -= vx * DRAG * TICK
		x += vx * TICK
		y += vy * TICK
		if y <= 0.0:
			var fraction := from_y / (from_y - y) if from_y > y else 1.0
			x = from_x + (x - from_x) * fraction
			y = 0.0
			_land()
	if not done:
		_touch_items(from_x, from_y + RADIUS, x, y + RADIUS)
	vx = clampf(vx, 0.0, 150.0)
	vy = clampf(vy, -90.0, 90.0)
	if y > max_height:
		max_height = y
	tick += 1
	if tick >= MAX_TICKS and not done:
		_finish()
	return applied

func distance_cm() -> int:
	return int(floor(x * 100.0))

func _land() -> void:
	var impact := -vy
	var slam := diving
	if diving:
		impact = _dive_impact
		diving = false
	if _touch_ground_pad(x, impact, slam):
		return
	vy = impact * RESTITUTION
	vx *= GROUND_GRIP
	if vy < 2.6:
		vy = 0.0
		rolling = true
	_emit("bounce", -1, impact)

## Springs and mud act on whatever is touching the ground at ground_x.
func _touch_ground_pad(ground_x: float, impact: float, slam: bool) -> bool:
	for item: Dictionary in course.near(ground_x):
		if item.w <= 0.0 or consumed.has(item.id) or absf(item.x - ground_x) > item.w + 0.3:
			continue
		if item.kind == Course.Kind.SPRING:
			vy = maxf(impact * 0.9, 11.0) + 6.0
			if slam:
				vy *= 1.25
			vx += 4.0
			y = 0.0
			rolling = false
			consumed[item.id] = true
			_emit("slam_spring" if slam else "spring", item.id, vy)
			return true
		if item.kind == Course.Kind.MUD:
			vx *= 0.3
			vy = 0.0
			rolling = true
			consumed[item.id] = true
			_emit("mud", item.id)
			return true
	return false

func _touch_items(ax: float, ay: float, bx: float, by: float) -> void:
	for item: Dictionary in course.near(bx):
		if item.w > 0.0 or consumed.has(item.id):
			continue
		var reach: float = item.r + RADIUS
		if item.x < ax - reach or item.x > bx + reach:
			continue
		if _segment_distance_squared(item.x, item.y, ax, ay, bx, by) > reach * reach:
			continue
		consumed[item.id] = true
		match item.kind:
			Course.Kind.BARREL:
				vx += 15.0
				vy = maxf(vy, 0.0) + 14.0
				_lift_off()
				_emit("barrel", item.id)
			Course.Kind.CACTUS:
				vx *= 0.5
				vy = maxf(vy, 0.0) * 0.3 + 5.0
				_lift_off()
				_emit("cactus", item.id)
			Course.Kind.RING:
				vx = vx * 1.15 + 7.0
				vy = maxf(vy, -4.0) + 3.0
				diving = false
				_emit("ring", item.id)
			Course.Kind.WINGMAN:
				vx += 2.5
				vy = maxf(vy, 0.0) * 0.4 + 12.0
				diving = false
				_emit("wingman", item.id)
			Course.Kind.FUEL:
				thrusts = mini(thrusts + 1, MAX_THRUSTS)
				_emit("fuel", item.id)
			Course.Kind.STORM:
				vx *= 0.8
				vy = minf(vy, 0.0) - 14.0
				diving = false
				_emit("storm", item.id)
			Course.Kind.COIN:
				coins += 1
				vx += 0.5
				_emit("coin", item.id)

func _lift_off() -> void:
	rolling = false
	diving = false
	if y <= 0.0:
		y = 0.01

func _finish() -> void:
	done = true
	rolling = false
	diving = false
	vx = 0.0
	vy = 0.0
	_emit("stop")

func _emit(kind: String, id: int = -1, strength: float = 0.0) -> void:
	events.append({"kind": kind, "x": x, "y": y, "id": id, "strength": strength})

static func _segment_distance_squared(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
	var dx := bx - ax
	var dy := by - ay
	var length := dx * dx + dy * dy
	var t := 0.0
	if length > 0.0:
		t = clampf(((px - ax) * dx + (py - ay) * dy) / length, 0.0, 1.0)
	var cx := ax + dx * t - px
	var cy := ay + dy * t - py
	return cx * cx + cy * cy

## Taylor series with basic arithmetic only; the launch angle stays within
## 0.34..1.23 rad where eleven terms are exact to double precision.
static func sine(angle: float) -> float:
	var square := angle * angle
	var term := angle
	var total := angle
	for n in range(1, 12):
		term *= -square / float((2 * n) * (2 * n + 1))
		total += term
	return total

static func cosine(angle: float) -> float:
	var square := angle * angle
	var term := 1.0
	var total := 1.0
	for n in range(1, 12):
		term *= -square / float((2 * n - 1) * (2 * n))
		total += term
	return total

## Input log wire format: runs of <letter><ticks since previous input>, where
## t = thrust and d = dive. "t12d40" = thrust at tick 12, dive at tick 52.
static func encode_inputs(log: Array) -> String:
	var text := ""
	var previous := 0
	for entry: Array in log:
		text += ("t" if entry[1] == IN_THRUST else "d") + str(int(entry[0]) - previous)
		previous = int(entry[0])
	return text

## Returns null for anything malformed; hosts must not trust this string.
static func decode_inputs(text: String) -> Variant:
	if text.length() > 900:
		return null
	var log: Array = []
	var at := 0
	var index := 0
	while index < text.length():
		var letter := text[index]
		if letter != "t" and letter != "d":
			return null
		index += 1
		var start := index
		while index < text.length() and text[index] >= "0" and text[index] <= "9":
			index += 1
		if index == start or index - start > 5:
			return null
		at += int(text.substr(start, index - start))
		if at >= MAX_TICKS or log.size() >= MAX_INPUTS:
			return null
		log.append([at, IN_THRUST if letter == "t" else IN_DIVE])
	return log

## Replays a whole flight. Used by tests, bots and host verification.
static func replay(course_seed: int, angle_decideg: int, power_permille: int, log: Array) -> RefCounted:
	var flight: RefCounted = load("res://game/sim/flight.gd").new(course_seed)
	flight.launch(angle_decideg, power_permille)
	var next := 0
	while not flight.done:
		var input := 0
		while next < log.size() and int(log[next][0]) <= flight.tick:
			if int(log[next][0]) == flight.tick:
				input |= int(log[next][1])
			next += 1
		flight.step(input)
		flight.events.clear()
	return flight
