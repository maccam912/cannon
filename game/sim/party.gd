extends RefCounted
## Host-side rules for a party match. No nodes, no networking: tests can play
## a whole match by calling tick().
##
## Everyone gets the same course each round and launches at the same time.
## Clients fly locally, then submit what they did (angle, power, input log).
## The host replays that through the deterministic Flight and scores its own
## answer, so a client can never just claim a distance.

const Flight := preload("res://game/sim/flight.gd")
const Rng := preload("res://game/sim/rng.gd")

enum Phase { LOBBY, COUNTDOWN, PLAYING, RESULTS, FINAL }

const HOST_ID := 1
const MAX_PLAYERS := 8
const COUNTDOWN_TICKS := 60 * 3
## Clients must fire within AIM_TICKS; the round itself is hard-capped.
const AIM_TICKS := 60 * 15
const ROUND_TICKS := AIM_TICKS + Flight.MAX_TICKS + 60 * 10
const RESULTS_TICKS := 60 * 12
const ROUND_CHOICES := [1, 3, 5]
## Flight ticks replayed per host tick, so verifying never stalls a frame.
const VERIFY_BUDGET := 1500

var phase := Phase.LOBBY
var round_number := 0
var rounds := 3
var round_seed := 0
var timer := 0
## id -> {name, slot, total_cm, round_cm, best_cm, playing}
## round_cm: -1 still flying, otherwise this round's verified distance.
var players: Dictionary = {}
## Bumped whenever something a client should hear about changed.
var roster_revision := 0
var phase_revision := 0

var _match_seed: int
var _jobs: Array = []

func _init(match_seed: int = 1) -> void:
	_match_seed = match_seed

func add_player(id: int, player_name: String) -> bool:
	if players.has(id) or players.size() >= MAX_PLAYERS:
		return false
	var used: Dictionary = {}
	for player: Dictionary in players.values():
		used[player.slot] = true
	var slot := 0
	while used.has(slot):
		slot += 1
	# Arriving during the countdown still makes this round; later than that
	# you watch it and play from the next one.
	players[id] = {"name": clean_name(player_name, id), "slot": slot, "total_cm": 0,
			"round_cm": -1, "best_cm": 0, "playing": phase == Phase.COUNTDOWN}
	roster_revision += 1
	return true

func remove_player(id: int) -> void:
	if not players.erase(id):
		return
	_jobs = _jobs.filter(func(job: Dictionary) -> bool: return job.id != id)
	roster_revision += 1

func set_rounds(by: int, count: int) -> bool:
	if by != HOST_ID or phase != Phase.LOBBY or not count in ROUND_CHOICES:
		return false
	rounds = count
	phase_revision += 1
	return true

func start(by: int) -> bool:
	if by != HOST_ID or not phase in [Phase.LOBBY, Phase.FINAL] or players.is_empty():
		return false
	for player: Dictionary in players.values():
		player.total_cm = 0
		player.best_cm = 0
	round_number = 0
	_match_seed = Rng.mix(_match_seed, 0x51ED)
	_begin_round()
	return true

## RESULTS -> next round or FINAL; FINAL -> LOBBY.
func advance(by: int) -> bool:
	if by != HOST_ID:
		return false
	if phase == Phase.RESULTS:
		if round_number >= rounds:
			_set_phase(Phase.FINAL)
		else:
			_begin_round()
		return true
	if phase == Phase.FINAL:
		_set_phase(Phase.LOBBY)
		return true
	return false

## A client's account of its flight. Rejected unless it is this round's, from
## someone still owed a result, and well formed; the distance is never sent.
func submit(id: int, for_round: Variant, angle: Variant, power: Variant, inputs: Variant) -> bool:
	if phase != Phase.PLAYING or not players.has(id):
		return false
	var player: Dictionary = players[id]
	if not player.playing or player.round_cm >= 0 or _has_job(id):
		return false
	if not _whole(for_round) or int(for_round) != round_number or not _whole(angle) or not _whole(power) or not inputs is String:
		return false
	if int(angle) < Flight.MIN_ANGLE or int(angle) > Flight.MAX_ANGLE or int(power) < 0 or int(power) > Flight.MAX_POWER:
		return false
	var log: Variant = Flight.decode_inputs(inputs)
	if log == null:
		return false
	var flight := Flight.new(round_seed)
	flight.launch(int(angle), int(power))
	_jobs.append({"id": id, "flight": flight, "log": log, "next": 0})
	return true

func tick() -> void:
	timer += 1
	match phase:
		Phase.COUNTDOWN:
			if timer >= COUNTDOWN_TICKS:
				_set_phase(Phase.PLAYING)
		Phase.PLAYING:
			_verify()
			if timer >= ROUND_TICKS:
				# Anyone who never reported lands at zero.
				_jobs.clear()
				for player: Dictionary in players.values():
					if player.playing and player.round_cm < 0:
						player.round_cm = 0
				roster_revision += 1
			if _round_complete():
				_set_phase(Phase.RESULTS)
		Phase.RESULTS:
			if timer >= RESULTS_TICKS:
				advance(HOST_ID)

## Ticks left in the current phase's clock, for countdown displays.
func ticks_left() -> int:
	match phase:
		Phase.COUNTDOWN:
			return maxi(COUNTDOWN_TICKS - timer, 0)
		Phase.PLAYING:
			return maxi(ROUND_TICKS - timer, 0)
		Phase.RESULTS:
			return maxi(RESULTS_TICKS - timer, 0)
	return 0

## Ids ordered by match total, then best single launch, then join order.
func standings() -> Array:
	var ids := players.keys()
	ids.sort_custom(func(a: int, b: int) -> bool:
		var left: Dictionary = players[a]
		var right: Dictionary = players[b]
		if left.total_cm != right.total_cm:
			return left.total_cm > right.total_cm
		if left.best_cm != right.best_cm:
			return left.best_cm > right.best_cm
		return a < b)
	return ids

static func clean_name(value: Variant, id: int) -> String:
	var text := ""
	if value is String:
		for character: String in (value as String).strip_edges().left(12):
			# Printable, and nothing that could masquerade as markup.
			if character.unicode_at(0) >= 32 and not character in "[]<>":
				text += character
	return text if not text.strip_edges().is_empty() else "Player %d" % id

func _begin_round() -> void:
	round_number += 1
	round_seed = Rng.mix(_match_seed, round_number)
	_jobs.clear()
	for player: Dictionary in players.values():
		player.round_cm = -1
		player.playing = true
	roster_revision += 1
	_set_phase(Phase.COUNTDOWN)

func _set_phase(next: int) -> void:
	phase = next
	timer = 0
	if next == Phase.LOBBY:
		round_number = 0
		for player: Dictionary in players.values():
			player.round_cm = -1
			player.playing = false
		roster_revision += 1
	phase_revision += 1

func _verify() -> void:
	var budget := VERIFY_BUDGET
	while budget > 0 and not _jobs.is_empty():
		var job: Dictionary = _jobs[0]
		var flight: Flight = job.flight
		var log: Array = job.log
		while budget > 0 and not flight.done:
			var input := 0
			if job.next < log.size() and int(log[job.next][0]) == flight.tick:
				input = int(log[job.next][1])
				job.next += 1
			flight.step(input)
			flight.events.clear()
			budget -= 1
		if flight.done:
			_jobs.pop_front()
			if players.has(job.id):
				var player: Dictionary = players[job.id]
				player.round_cm = flight.distance_cm()
				player.total_cm += player.round_cm
				player.best_cm = maxi(player.best_cm, player.round_cm)
				roster_revision += 1

func _round_complete() -> bool:
	if not _jobs.is_empty():
		return false
	var anyone := false
	for player: Dictionary in players.values():
		if player.playing:
			anyone = true
			if player.round_cm < 0:
				return false
	# Everyone who was playing left: do not hang in an empty round.
	return anyone or timer > COUNTDOWN_TICKS

func _has_job(id: int) -> bool:
	for job: Dictionary in _jobs:
		if job.id == id:
			return true
	return false

static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and absf(float(value)) < 2147483647.0
