extends "res://tests/harness.gd"
## Flight, course and aim rules, with no nodes or networking involved.

const Rng := preload("res://game/sim/rng.gd")
const Course := preload("res://game/sim/course.gd")
const Flight := preload("res://game/sim/flight.gd")
const Aim := preload("res://game/sim/aim.gd")

## Recorded on Apple Silicon. CI replays them on x86 Linux and Windows, so a
## mismatch there means flights are no longer identical across devices.
const GOLDEN := [
	[12345, 450, 800, "t30d40t25", 20876],
	[777, 300, 1000, "d50t10d60t40", 36600],
	[2026, 620, 400, "", 8086],
]

func label() -> String:
	return "SIM"

func run() -> void:
	_rng()
	_course()
	_physics()
	_inputs()
	_aim()
	_golden()
	_survey()

func _rng() -> void:
	var a := Rng.new(42)
	var b := Rng.new(42)
	var c := Rng.new(43)
	var same := true
	var different := false
	for _i in 100:
		var value := a.next_u32()
		same = same and value == b.next_u32()
		different = different or value != c.next_u32()
		check(value >= 0 and value <= 0xFFFFFFFF, "rng stays in 32 bits")
	check(same, "same seed, same sequence")
	check(different, "different seed, different sequence")
	check(a.unit() >= 0.0 and a.unit() < 1.0, "unit in range")

func _course() -> void:
	var first := Course.new(9)
	var second := Course.new(9)
	check(str(first.chunk(7)) == str(second.chunk(7)), "chunks are reproducible")
	check(str(first.chunk(7)) != str(Course.new(10).chunk(7)), "seeds change the course")
	var ids: Dictionary = {}
	var kinds: Dictionary = {}
	for index in 60:
		for item: Dictionary in first.chunk(index):
			check(not ids.has(item.id), "item ids are unique")
			ids[item.id] = true
			kinds[item.kind] = true
			check(item.x >= Course.CLEAR_START - 5.0, "runway stays clear")
			check(item.x >= index * Course.CHUNK - 5.0 and item.x <= (index + 1) * Course.CHUNK + 5.0, "item sits in its chunk")
	check(kinds.size() == Course.Kind.size(), "every kind of item appears")
	check(first.chunk(-1).is_empty(), "nothing behind the cannon")

func _bare(angle: int, power: int) -> Flight:
	var flight := Flight.new(1)
	flight.course.enabled = false
	flight.launch(angle, power)
	return flight

func _finish(flight: Flight) -> Flight:
	while not flight.done:
		flight.step()
	return flight

func _physics() -> void:
	var weak := _finish(_bare(450, 200))
	var strong := _finish(_bare(450, 900))
	check(weak.x > 10.0, "a weak launch still goes somewhere")
	check(strong.x > weak.x * 1.5, "more power flies further")
	check(strong.tick < Flight.MAX_TICKS, "bare flights settle on their own")
	check(strong.y == 0.0 and strong.vx == 0.0, "stopped on the ground")
	check(_finish(_bare(450, 1000)).x > _finish(_bare(450, 930)).x * 1.05, "perfect pressure gets a bonus")
	check(absf(Flight.sine(0.7) - sin(0.7)) < 1e-12 and absf(Flight.cosine(1.2) - cos(1.2)) < 1e-12, "series trig is accurate")

	# Thrust: limited charges, each one really pushes.
	var thrusty := _bare(450, 500)
	var used := 0
	for index in 400:
		if thrusty.step(Flight.IN_THRUST) & Flight.IN_THRUST:
			used += 1
	check(used == Flight.START_THRUSTS and thrusty.thrusts == 0, "only three thrusts")
	check(_finish(thrusty).x > _finish(_bare(450, 500)).x + 20.0, "thrusts add distance")

	# Dive: lands sooner, hits no harder, so it cannot be farmed for energy.
	var plain := _bare(600, 800)
	var diver := _bare(600, 800)
	for _i in 60:
		plain.step()
		diver.step()
	check(diver.step(Flight.IN_DIVE) == Flight.IN_DIVE, "dive accepted in the air")
	check(diver.step(Flight.IN_DIVE) == 0, "no double dive")
	plain.step()
	plain.step()
	var plain_bounce := _first_bounce(plain)
	var dive_bounce := _first_bounce(diver)
	check(dive_bounce.tick < plain_bounce.tick, "diving lands sooner")
	check(absf(dive_bounce.strength - plain_bounce.strength) < 0.8, "dive impact matches the natural fall")
	var spam := _bare(450, 800)
	while not spam.done:
		spam.step(Flight.IN_DIVE)
	check(spam.x < _finish(_bare(450, 800)).x + 1.0, "spamming dive gains nothing on bare ground")

	# Each item does what it says.
	check(_effect(Course.Kind.SPRING, 0.0, 0.0).vy > 10.0, "spring launches")
	check(_effect(Course.Kind.MUD, 0.0, 0.0).vx < 10.0, "mud grabs")
	check(_effect(Course.Kind.BARREL, 0.9, 0.95).vx > 30.0, "barrel blasts forward")
	check(_effect(Course.Kind.CACTUS, 1.3, 1.0).vx < 14.0, "cactus hurts")
	check(_effect(Course.Kind.RING, 0.6, 1.6).vx > 26.0, "ring boosts")
	check(_effect(Course.Kind.WINGMAN, 0.6, 1.3).vy > 10.0, "wingman bounces you up")
	check(_effect(Course.Kind.STORM, 0.6, 1.9).vy < -10.0, "storm swats you down")
	check(_effect(Course.Kind.FUEL, 0.6, 1.1).thrusts == Flight.START_THRUSTS + 1, "fuel refills")
	check(_effect(Course.Kind.COIN, 0.6, 0.8).coins == 1, "coin collected")

func _first_bounce(flight: Flight) -> Dictionary:
	while not flight.done:
		flight.events.clear()
		flight.step()
		for event: Dictionary in flight.events:
			if event.kind == "bounce":
				return {"tick": flight.tick, "strength": event.strength}
	return {"tick": -1, "strength": 0.0}

## Rolls a cannonaut along the ground at 20 m/s into a single item.
func _effect(kind: int, y: float, r: float) -> Flight:
	var flight := Flight.new(1)
	flight.course._chunks = {0: [{"id": 1, "kind": kind, "x": 6.0, "y": y, "r": r, "w": 1.6 if r == 0.0 else 0.0}]}
	for index in range(-1, 40):
		if index != 0:
			flight.course._chunks[index] = []
	flight.x = 0.0
	flight.y = 0.0
	flight.vx = 20.0
	flight.rolling = true
	for _i in 60:
		flight.step()
		if flight.consumed.has(1):
			break
	check(flight.consumed.has(1), "item %s was touched" % Course.NAMES[kind])
	return flight

func _inputs() -> void:
	var log := [[5, Flight.IN_THRUST], [40, Flight.IN_DIVE], [41, Flight.IN_THRUST], [900, Flight.IN_DIVE]]
	var text := Flight.encode_inputs(log)
	check(text == "t5d35t1d859", "compact input encoding")
	check(str(Flight.decode_inputs(text)) == str(log), "inputs survive a round trip")
	check(Flight.decode_inputs("") == [], "empty log is fine")
	for bad in ["x5", "t", "t-5", "5t", "t999999", "t5 d5", "d%d" % Flight.MAX_TICKS, "t1".repeat(Flight.MAX_INPUTS + 1), "t1".repeat(600)]:
		check(Flight.decode_inputs(bad) == null, "rejects malformed input log " + bad.left(12))

	# Stepping live and replaying the recorded log must agree exactly.
	var rng := Rng.new(5)
	for trial in 20:
		var live := Flight.new(1000 + trial)
		var angle := 200 + rng.next_u32() % 501
		var power := rng.next_u32() % 1001
		live.launch(angle, power)
		var recorded: Array = []
		while not live.done:
			var want := 0
			if rng.unit() < 0.03:
				want = Flight.IN_THRUST if rng.unit() < 0.3 else Flight.IN_DIVE
			var at := live.tick
			var applied := live.step(want)
			if applied != 0 and recorded.size() < Flight.MAX_INPUTS:
				recorded.append([at, applied])
		var again: Flight = Flight.replay(1000 + trial, angle, power, Flight.decode_inputs(Flight.encode_inputs(recorded)))
		check(again.distance_cm() == live.distance_cm() and again.tick == live.tick and again.coins == live.coins,
				"replay %d matches the live flight (%d vs %d)" % [trial, again.distance_cm(), live.distance_cm()])

func _aim() -> void:
	var aim := Aim.new()
	for pump in Aim.PUMPS:
		check(aim.stage == Aim.Stage.PUMP, "pumping")
		for _i in Aim.PUMP_SWEEPS[pump]:
			aim.advance()
		check(aim.gauge == 1.0, "gauge peaks after one sweep")
		check(aim.tap().perfect, "tap at the peak is perfect")
	check(aim.power_permille == 1000 and aim.stage == Aim.Stage.ANGLE, "three perfect pumps is full pressure")
	for _i in Aim.ANGLE_SWEEP / 2:
		aim.advance()
	check(absi(aim.angle_decideg - 450) <= 5, "needle crosses 45 degrees mid sweep")
	check(aim.tap().kind == "fire" and aim.stage == Aim.Stage.FIRED, "fourth tap fires")
	check(aim.tap().is_empty(), "nothing after firing")
	var lazy := Aim.new()
	lazy.advance()
	lazy.force()
	check(lazy.stage == Aim.Stage.FIRED and lazy.power_permille < 100, "running out of time fires a weak shot")
	check(lazy.angle_decideg >= Flight.MIN_ANGLE and lazy.angle_decideg <= Flight.MAX_ANGLE, "forced angle is legal")

func _golden() -> void:
	var report := "GOLDEN"
	for row: Array in GOLDEN:
		var flight: Flight = Flight.replay(row[0], row[1], row[2], Flight.decode_inputs(row[3]))
		report += " %d" % flight.distance_cm()
		check(flight.distance_cm() == row[4], "golden flight seed %d: got %d cm, expected %d" % [row[0], flight.distance_cm(), row[4]])
	print(report)

## Tuning aid and safety net: lots of bot flights must end, and the spread of
## distances shows whether skill matters.
func _survey() -> void:
	var rng := Rng.new(99)
	var idle: Array = []
	var busy: Array = []
	var longest := 0
	for trial in 120:
		var angle := 300 + rng.next_u32() % 300
		var power := 500 + rng.next_u32() % 501
		var quiet: Flight = Flight.replay(5000 + trial, angle, power, [])
		idle.append(quiet.distance_cm() / 100)
		var flight := Flight.new(5000 + trial)
		flight.launch(angle, power)
		while not flight.done:
			# A crude bot: thrust when about to land slowly, dive at springs.
			var want := 0
			if flight.y < 1.0 and flight.vy < 0.0 and flight.vx < 18.0:
				want = Flight.IN_THRUST
			elif flight.y > 2.0:
				for item: Dictionary in flight.course.near(flight.x):
					if item.kind == Course.Kind.SPRING and item.x > flight.x and item.x - flight.x < flight.vx * 0.35:
						want = Flight.IN_DIVE
			flight.step(want)
			flight.events.clear()
		busy.append(flight.distance_cm() / 100)
		longest = maxi(longest, flight.tick)
		check(flight.tick <= Flight.MAX_TICKS, "flight ends in time")
	idle.sort()
	busy.sort()
	print("SURVEY idle median %d m (p90 %d, max %d) · bot median %d m (p90 %d, max %d) · longest %d s" % [
			idle[idle.size() / 2], idle[idle.size() * 9 / 10], idle[-1], busy[busy.size() / 2], busy[busy.size() * 9 / 10], busy[-1], longest / 60])
	check(idle[idle.size() / 2] > 80, "idle flights are not pathetic")
	check(busy[busy.size() / 2] > idle[idle.size() / 2], "playing well beats doing nothing")
