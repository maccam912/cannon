extends RefCounted
## Integer xorshift32. Only 64-bit integer ops with explicit masks, so the
## sequence is identical on every CPU and OS (course layouts must match).

var state: int

func _init(seed_value: int = 1) -> void:
	state = (seed_value ^ 0x9E3779B9) & 0xFFFFFFFF
	if state == 0:
		state = 0x6D2B79F5
	for _i in 4:
		next_u32()

func next_u32() -> int:
	state ^= (state << 13) & 0xFFFFFFFF
	state ^= state >> 17
	state ^= (state << 5) & 0xFFFFFFFF
	return state

## Uniform in [0, 1). Division by a power of two is exact in IEEE doubles.
func unit() -> float:
	return float(next_u32()) / 4294967296.0

func range_f(low: float, high: float) -> float:
	return low + (high - low) * unit()

## Picks an index from integer weights.
func pick(weights: Array) -> int:
	var total := 0
	for weight: int in weights:
		total += weight
	var roll := next_u32() % total
	for index in weights.size():
		roll -= int(weights[index])
		if roll < 0:
			return index
	return weights.size() - 1

static func mix(a: int, b: int) -> int:
	var value := (((a & 0xFFFFFFFF) * 73856093) ^ ((b & 0xFFFFFFFF) * 19349663)) & 0xFFFFFFFF
	value ^= value >> 15
	value = (value * 0x2C1B3C6D) & 0xFFFFFFFF
	value ^= value >> 12
	return value
