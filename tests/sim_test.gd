extends "res://tests/harness.gd"
## Flight, course and aim rules, with no nodes or networking involved.

const Rng := preload("res://game/sim/rng.gd")
const Course := preload("res://game/sim/course.gd")
const Flight := preload("res://game/sim/flight.gd")
const Aim := preload("res://game/sim/aim.gd")
const Upgrades := preload("res://game/sim/upgrades.gd")

## Recorded on Apple Silicon. CI replays them on x86 Linux and Windows, so a
## mismatch there means flights are no longer identical across devices.
const MAXED := {"powder": 10, "rubber": 10, "springs": 10, "farm": 10, "thrusters": 5, "slipstream": 10, "luck": 10}
const GOLDEN := [
	[12345, 450, 800, "t30d40t25", 20876, {}],
	[777, 300, 1000, "d50t10d60t40", 36600, {}],
	[2026, 620, 400, "", 8086, {}],
	[4242, 400, 900, "t20d45t30d60", 85741, {"powder": 5, "rubber": 5, "springs": 5, "farm": 5, "thrusters": 2, "slipstream": 5, "luck": 5}],
	[31337, 350, 1000, "d40t90", 90464, MAXED],
	# One of each wild course: boom town, spring fever, tailwind, moon day.
	[1, 400, 900, "t60", 655155, MAXED],
	[3, 400, 900, "t60", 783623, MAXED],
	[7, 400, 900, "t60", 443552, MAXED],
	[13, 400, 900, "t60", 360239, MAXED],
]

func label() -> String:
	return "SIM"

func run() -> void:
	_rng()
	_course()
	_physics()
	_inputs()
	_aim()
	_progression()
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
	check(used == Flight.START_THRUSTS and thrusty.thrusts == 0, "only three thrusts when stock")
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
	for bad in ["x5", "t", "t-5", "5t", "t999999", "t5 d5", "d%d" % Flight.MAX_TICKS, "t1".repeat(Flight.MAX_INPUTS + 1), "t1".repeat(4000)]:
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

func _upgraded(id: String, level: int, angle: int = 450, power: int = 800) -> Flight:
	var flight := Flight.new(1, {id: level})
	flight.course.enabled = false
	flight.launch(angle, power)
	return flight

func _progression() -> void:
	# Costs climb, presets are sane, junk input is cleaned.
	for id: String in Upgrades.IDS:
		check(Upgrades.cost(id, 0) == Upgrades.INFO[id].cost, "%s starts at its base cost" % id)
		for level in range(1, Upgrades.max_level(id)):
			check(Upgrades.cost(id, level) > Upgrades.cost(id, level - 1), "%s gets pricier" % id)
		check(not Upgrades.effect(id, 1).is_empty(), "%s describes itself" % id)
	check(Upgrades.cost("powder", 9) > 500 and Upgrades.cost("powder", 9) < 2000, "top levels cost hundreds, not millions")
	check(Upgrades.preset(0).powder == 0 and Upgrades.preset(1).powder == 5 and Upgrades.preset(2).thrusters == 5, "party presets")
	var junk := Upgrades.clean({"powder": 99, "rubber": -4, "luck": "lots", "farm": NAN, "bogus": 3})
	check(junk.powder == 10 and junk.rubber == 0 and junk.luck == 0 and junk.farm == 0 and not junk.has("bogus"), "levels are clamped and unknown ones dropped")
	check(Upgrades.clean(null).size() == Upgrades.IDS.size(), "nothing means stock")
	check(Upgrades.stars(25000, 0, false) == 25 and Upgrades.stars(25000, 4, true) == 47, "stars: distance, coins, perfect tip")

	# Each purchase does what its card says.
	var stock := _finish(_bare(450, 800))
	check(_finish(_upgraded("powder", 10)).x > stock.x * 1.8, "gunpowder launches much further")
	check(_finish(_upgraded("rubber", 10)).x > stock.x * 1.2, "rubber suit keeps bouncing")
	check(_finish(_upgraded("slipstream", 10)).x > stock.x * 1.03, "slipstream loses less speed")
	check(_upgraded("thrusters", 5).thrusts == 8 and _upgraded("thrusters", 5).max_thrusts == 10, "thrusters add charges")
	var spring := Flight.new(1, {"springs": 10})
	spring.course._chunks = {0: [{"id": 1, "kind": Course.Kind.SPRING, "x": 6.0, "y": 0.0, "r": 0.0, "w": 1.6}], -1: [], 1: []}
	spring.vx = 20.0
	spring.y = 0.0
	spring.rolling = true
	for _i in 40:
		spring.step()
		if spring.consumed.has(1):
			break
	check(spring.vy > _effect(Course.Kind.SPRING, 0.0, 0.0).vy * 1.6, "super springs fling harder")

	# Spring Farm only ever adds springs or swaps hazards for them.
	var plain := Course.new(77)
	var farmed := Course.new(77, 10)
	var before := _tally(plain)
	var after := _tally(farmed)
	check(after[Course.Kind.SPRING] > before[Course.Kind.SPRING] * 1.5, "farm grows springs (%d -> %d)" % [before[Course.Kind.SPRING], after[Course.Kind.SPRING]])
	check(after[Course.Kind.MUD] < before[Course.Kind.MUD] and after[Course.Kind.CACTUS] < before[Course.Kind.CACTUS], "farm replaces some hazards")
	check(after[Course.Kind.RING] == before[Course.Kind.RING] and after[Course.Kind.COIN] == before[Course.Kind.COIN], "farm leaves the sky alone")
	check(str(Course.new(77, 10).chunk(9)) == str(farmed.chunk(9)), "farmed courses are reproducible")

	# Wild courses: rarer without luck, same answer every time, real effects.
	var rare := 0
	var lucky := 0
	for trial in 2000:
		if Course.event_for(trial, 0) != Course.Event.NONE:
			rare += 1
		if Course.event_for(trial, 10) != Course.Event.NONE:
			lucky += 1
			check(Course.event_for(trial, 10) < Course.Event.size(), "event in range")
	check(rare > 60 and rare < 200, "about 6%% of stock courses are wild (%d of 2000)" % rare)
	check(lucky > 400 and lucky < 650, "about 26%% with full luck (%d of 2000)" % lucky)
	check(Course.event_for(123, 4) == Course.event_for(123, 4), "a seed's event never changes")
	var fever := _tally(Course.new(77, 0, Course.Event.SPRING_FEVER))
	check(fever[Course.Kind.SPRING] > before[Course.Kind.SPRING] * 2, "spring fever is mostly springs")
	var boom := _tally(Course.new(77, 0, Course.Event.BOOM_TOWN))
	check(boom[Course.Kind.BARREL] > before[Course.Kind.BARREL] * 2, "boom town is mostly barrels")
	var moon := Flight.new(1)
	moon.course.enabled = false
	moon._gravity = Flight.GRAVITY * 0.6
	moon.launch(450, 800)
	check(_finish(moon).x > stock.x * 1.4, "low gravity carries further")

func _tally(course: Course) -> Array:
	var counts: Array = []
	counts.resize(Course.Kind.size())
	counts.fill(0)
	for index in 80:
		for item: Dictionary in course.chunk(index):
			counts[item.kind] += 1
	return counts

func _golden() -> void:
	var report := "GOLDEN"
	for row: Array in GOLDEN:
		var flight: Flight = Flight.replay(row[0], row[1], row[2], Flight.decode_inputs(row[3]), row[5])
		report += " %d" % flight.distance_cm()
		check(flight.distance_cm() == row[4], "golden flight seed %d: got %d cm, expected %d" % [row[0], flight.distance_cm(), row[4]])
	print(report)
	for index in 4:
		check(Course.event_for(GOLDEN[5 + index][0], 10) == [2, 1, 3, 4][index], "golden seed %d is the wild course it claims" % GOLDEN[5 + index][0])

## A crude player: thrust when about to land slowly, dive onto springs.
func _bot_flight(course_seed: int, angle: int, power: int, levels: Dictionary) -> Flight:
	var flight := Flight.new(course_seed, levels)
	flight.launch(angle, power)
	while not flight.done:
		var want := 0
		if flight.y < 1.0 and flight.vy < 0.0 and flight.vx < 18.0:
			want = Flight.IN_THRUST
		elif flight.y > 2.0:
			for item: Dictionary in flight.course.near(flight.x):
				if item.kind == Course.Kind.SPRING and item.x > flight.x and item.x - flight.x < flight.vx * 0.35:
					want = Flight.IN_DIVE
		flight.step(want)
		flight.events.clear()
	return flight

## Tuning aid and safety net: lots of bot flights must end, and the spread of
## distances shows whether upgrades and luck deliver the occasional huge run.
func _survey() -> void:
	var rng := Rng.new(99)
	var shots: Array = []
	for trial in 150:
		shots.append([5000 + trial, 300 + rng.next_u32() % 300, 500 + rng.next_u32() % 501])
	var medians: Array = []
	for preset in 3:
		var levels := Upgrades.preset(preset)
		var distances: Array = []
		var times: Array = []
		var longest := 0
		var wild := 0
		for shot: Array in shots:
			var flight := _bot_flight(shot[0], shot[1], shot[2], levels)
			distances.append(flight.distance_cm() / 100)
			longest = maxi(longest, flight.tick)
			times.append(flight.tick / 60)
			if flight.event != Course.Event.NONE:
				wild += 1
			check(flight.tick <= Flight.MAX_TICKS, "flight ends in time")
		distances.sort()
		times.sort()
		medians.append(distances[distances.size() / 2])
		print("SURVEY %s: median %d m, p90 %d m, max %d m, %d wild, time median %d s / p90 %d s / max %d s, median stars %d" % [
				Upgrades.PRESET_NAMES[preset], distances[distances.size() / 2], distances[distances.size() * 9 / 10],
				distances[-1], wild, times[times.size() / 2], times[times.size() * 9 / 10], longest / 60,
				Upgrades.stars(distances[distances.size() / 2] * 100, 6, false)])
		check(distances[-1] > distances[distances.size() / 2] * 2.5, "%s has the occasional huge run" % Upgrades.PRESET_NAMES[preset])
	check(medians[0] > 80, "stock flights are not pathetic")
	check(medians[1] > medians[0] * 1.6 and medians[2] > medians[1] * 1.6, "upgrades clearly pay off: " + str(medians))
