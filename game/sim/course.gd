extends RefCounted
## Endless course generated in chunks from a seed. Everyone given the same
## seed gets the same springs, hazards and pickups at the same places.

const Rng := preload("res://game/sim/rng.gd")

const CHUNK := 64.0
const SLOTS := 4
const SLOT := CHUNK / SLOTS
const CLEAR_START := 40.0

enum Kind { SPRING, MUD, BARREL, CACTUS, RING, WINGMAN, FUEL, STORM, COIN }

const NAMES := ["spring", "mud", "barrel", "cactus", "ring", "wingman", "fuel", "storm", "coin"]

var seed_value: int
## Tests switch this off to study bare physics.
var enabled := true
var _chunks: Dictionary = {}
var _near_index := -1000000
var _near_items: Array = []

func _init(course_seed: int = 1) -> void:
	seed_value = course_seed

## Items are {id, kind, x, y, r, w}: y/r describe a circle (centre height and
## radius) for touch items, w is the half width of ground pads.
func chunk(index: int) -> Array:
	if index < 0 or not enabled:
		return []
	if not _chunks.has(index):
		_chunks[index] = _generate(index)
	return _chunks[index]

func _generate(index: int) -> Array:
	var rng := Rng.new(Rng.mix(seed_value, index))
	var items: Array = []
	var base := index * CHUNK
	# Hazards slowly crowd out help the further you get.
	var far := minf(index / 40.0, 1.0)
	var ground := [34 - int(10 * far), 24 + int(10 * far), 16, 18 + int(6 * far)]
	var air := [20, 24, 8, 14 + int(8 * far), 28]
	for slot in SLOTS:
		var left := base + slot * SLOT
		if rng.unit() < 0.7:
			var x := left + rng.range_f(3.0, SLOT - 3.0)
			var kind: int = [Kind.SPRING, Kind.MUD, Kind.BARREL, Kind.CACTUS][rng.pick(ground)]
			if x >= CLEAR_START:
				items.append(_ground_item(index, items.size(), kind, x))
		if rng.unit() < 0.62:
			var x := left + rng.range_f(2.0, SLOT - 2.0)
			var kind: int = [Kind.RING, Kind.WINGMAN, Kind.FUEL, Kind.STORM, Kind.COIN][rng.pick(air)]
			var height := rng.unit()
			if x < CLEAR_START:
				continue
			match kind:
				Kind.RING:
					items.append(_item(index, items.size(), kind, x, 4.0 + 14.0 * height, 1.6))
				Kind.WINGMAN:
					items.append(_item(index, items.size(), kind, x, 3.5 + 11.0 * height, 1.3))
				Kind.FUEL:
					items.append(_item(index, items.size(), kind, x, 5.0 + 11.0 * height, 1.1))
				Kind.STORM:
					items.append(_item(index, items.size(), kind, x, 10.0 + 14.0 * height, 1.9))
				Kind.COIN:
					# A five-coin arch to fly along.
					var start := 3.0 + 9.0 * height
					for step in 5:
						var lift := float(step * (4 - step)) * 0.55
						items.append(_item(index, items.size(), kind, x + step * 2.2 - 4.4, start + lift, 0.8))
	return items

func _ground_item(index: int, slot: int, kind: int, x: float) -> Dictionary:
	match kind:
		Kind.SPRING:
			return _item(index, slot, kind, x, 0.0, 0.0, 1.6)
		Kind.MUD:
			return _item(index, slot, kind, x, 0.0, 0.0, 2.3)
		Kind.BARREL:
			return _item(index, slot, kind, x, 0.9, 0.95)
		_:
			return _item(index, slot, kind, x, 1.3, 1.0)

func _item(index: int, slot: int, kind: int, x: float, y: float, r: float, w: float = 0.0) -> Dictionary:
	return {"id": index * 64 + slot, "kind": kind, "x": x, "y": y, "r": r, "w": w}

## Items in the chunk containing x and both neighbours.
func near(x: float) -> Array:
	var index := int(floor(x / CHUNK))
	if index != _near_index:
		_near_index = index
		_near_items = []
		for offset in [-1, 0, 1]:
			_near_items.append_array(chunk(index + offset))
	return _near_items
