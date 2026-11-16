extends RefCounted
## The launch ritual: three timed pumps build pressure, then one tap picks the
## angle and fires. Four taps total, playable with one thumb.

const Flight := preload("res://game/sim/flight.gd")

enum Stage { PUMP, ANGLE, FIRED }

const PUMPS := 3
## Ticks for the gauge to fill once; every pump is faster than the last.
const PUMP_SWEEPS := [52, 40, 30]
const ANGLE_SWEEP := 66
const PERFECT := 0.92

var stage := Stage.PUMP
var pump := 0
var scores: Array = []
var gauge := 0.0     # 0..1 pressure needle during a pump
var needle := 0.0    # 0..1 across the angle arc
var angle_decideg := 450
var power_permille := 0
var _clock := 0

func advance() -> void:
	if stage == Stage.FIRED:
		return
	_clock += 1
	if stage == Stage.PUMP:
		gauge = _triangle(_clock, PUMP_SWEEPS[pump])
	else:
		needle = _triangle(_clock, ANGLE_SWEEP)
		angle_decideg = Flight.MIN_ANGLE + int(round(needle * (Flight.MAX_ANGLE - Flight.MIN_ANGLE)))

## Returns what the tap did: {"kind": "pump", "score": 0..1, "perfect": bool}
## or {"kind": "fire"}; empty once fired.
func tap() -> Dictionary:
	if stage == Stage.PUMP:
		var score := 1.0 if gauge >= PERFECT else gauge
		scores.append(score)
		pump += 1
		_clock = 0
		gauge = 0.0
		var total := 0.0
		for value: float in scores:
			total += value
		power_permille = int(round(total / PUMPS * 1000.0))
		if pump >= PUMPS:
			stage = Stage.ANGLE
		return {"kind": "pump", "score": score, "perfect": score >= 1.0}
	if stage == Stage.ANGLE:
		stage = Stage.FIRED
		return {"kind": "fire"}
	return {}

## Out of time: finish with whatever the gauges show right now.
func force() -> void:
	while stage != Stage.FIRED:
		tap()

func pressure() -> float:
	return power_permille / 1000.0

static func _triangle(clock: int, sweep: int) -> float:
	var phase := clock % (sweep * 2)
	return float(phase) / sweep if phase <= sweep else float(sweep * 2 - phase) / sweep
