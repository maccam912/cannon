extends "res://tests/harness.gd"
## Plays whole party matches against the host rules, no network involved.

const Party := preload("res://game/sim/party.gd")
const Flight := preload("res://game/sim/flight.gd")
const Upgrades := preload("res://game/sim/upgrades.gd")

func label() -> String:
	return "PARTY"

func run() -> void:
	_full_match()
	_rejections()
	_timeouts_and_leavers()
	_lobby_rules()
	_power()

func _ticks(party: Party, count: int) -> void:
	for _i in count:
		party.tick()

func _until(party: Party, phase: int, limit: int = 100000) -> bool:
	for _i in limit:
		if party.phase == phase:
			return true
		party.tick()
	return party.phase == phase

func _full_match() -> void:
	var party := Party.new(4242)
	check(party.add_player(1, "Host"), "host joins")
	check(party.add_player(2, "  Ada  "), "client joins")
	check(party.add_player(3, ""), "nameless client joins")
	check(party.players[2].name == "Ada" and party.players[3].name == "Player 3", "names are cleaned")
	check(party.players[1].slot != party.players[2].slot and party.players[2].slot != party.players[3].slot, "distinct colours")
	check(not party.start(2), "only the host starts")
	check(party.set_rounds(1, 3) and not party.set_rounds(2, 5) and not party.set_rounds(1, 4), "host picks 1/3/5 rounds")
	check(party.start(1), "host starts")
	var seeds: Dictionary = {}
	# Player 2 always pumps perfectly, player 3 always fluffs it.
	var shots := {1: [450, 700, "t20"], 2: [420, 1000, "t30t30t30"], 3: [450, 50, ""]}
	for number in range(1, 4):
		check(party.phase == Party.Phase.COUNTDOWN and party.round_number == number, "round %d counts down" % number)
		check(not party.submit(1, number, 450, 500, ""), "no results during the countdown")
		check(_until(party, Party.Phase.PLAYING, Party.COUNTDOWN_TICKS + 1), "round %d starts" % number)
		seeds[party.round_seed] = true
		for id: int in shots:
			check(party.submit(id, number, shots[id][0], shots[id][1], shots[id][2]), "player %d submits" % id)
			check(not party.submit(id, number, 450, 1000, ""), "no second submission")
		check(_until(party, Party.Phase.RESULTS, 2000), "round %d resolves once everyone landed" % number)
		for id: int in shots:
			var expected: Flight = Flight.replay(party.round_seed, shots[id][0], shots[id][1], Flight.decode_inputs(shots[id][2]))
			check(party.players[id].round_cm == expected.distance_cm(), "host scored player %d by its own replay" % id)
		check(party.advance(1), "host moves on")
	check(seeds.size() == 3, "every round has a fresh course")
	check(party.phase == Party.Phase.FINAL, "match ends after three rounds")
	var order := party.standings()
	check(order.size() == 3 and order[0] == 2 and order[2] == 3, "best total wins: " + str(order))
	check(party.players[2].total_cm > party.players[3].total_cm, "totals accumulate")
	check(party.players[2].best_cm <= party.players[2].total_cm and party.players[2].best_cm > 0, "best launch tracked")
	check(not party.advance(3), "clients cannot advance")
	check(party.advance(1) and party.phase == Party.Phase.LOBBY, "back to the lobby")
	check(party.start(1) and party.players[2].total_cm == 0, "a rematch starts from zero")

func _rejections() -> void:
	var party := Party.new(7)
	party.add_player(1, "Host")
	party.add_player(2, "Sneaky")
	party.start(1)
	_until(party, Party.Phase.PLAYING)
	var bad := [
		[2, 1, 450, 5000, ""], [2, 1, 900, 500, ""], [2, 1, 100, 500, ""], [2, 1, 450, -1, ""],
		[2, 2, 450, 500, ""], [2, 1, 450.5, 500, ""], [2, 1, "450", 500, ""], [2, 1, 450, 500, 12],
		[2, 1, 450, 500, "zzz"], [2, 1, 450, 500, "t1".repeat(4000)], [2, 1, NAN, 500, ""], [2, 1, 450, INF, ""],
		[9, 1, 450, 500, ""], [2, null, 450, 500, ""],
	]
	for row: Array in bad:
		check(not party.submit(row[0], row[1], row[2], row[3], row[4]), "rejects " + str(row).left(40))
	check(party.submit(2, 1, 450, 500, ""), "an honest shot is still accepted afterwards")
	# Inputs that could not have happened (thrust without charges) do nothing.
	var party2 := Party.new(7)
	party2.add_player(1, "Host")
	party2.start(1)
	_until(party2, Party.Phase.PLAYING)
	check(party2.submit(1, 1, 450, 500, "t20t20t20t20t20t20t20t20"), "extra thrusts are accepted as a log")
	_until(party2, Party.Phase.RESULTS)
	var honest: Flight = Flight.replay(party2.round_seed, 450, 500, Flight.decode_inputs("t20t20t20"))
	check(party2.players[1].round_cm == honest.distance_cm(), "but only three thrusts ever fire")

func _timeouts_and_leavers() -> void:
	var party := Party.new(11)
	for id in [1, 2, 3]:
		party.add_player(id, "P%d" % id)
	party.set_rounds(1, 1)
	party.start(1)
	check(party.add_player(5, "Just") and party.players[5].playing, "joining during the countdown still plays")
	party.remove_player(5)
	_until(party, Party.Phase.PLAYING)
	check(party.add_player(4, "Late") and not party.players[4].playing, "late joiner sits this round out")
	check(not party.submit(4, 1, 450, 500, ""), "and cannot score in it")
	party.submit(1, 1, 450, 500, "")
	_ticks(party, 600)
	check(party.phase == Party.Phase.PLAYING, "still waiting for the others")
	party.remove_player(2)
	_ticks(party, 10)
	check(party.phase == Party.Phase.PLAYING, "one player still owes a result")
	check(_until(party, Party.Phase.RESULTS, Party.ROUND_TICKS + 10), "the round clock ends it")
	check(party.players[3].round_cm == 0 and party.players[1].round_cm > 0, "no-shows score zero")
	check(_until(party, Party.Phase.FINAL, Party.RESULTS_TICKS + 10), "results auto-advance to the final")
	# Everyone leaving mid-round must not strand the host.
	var lonely := Party.new(3)
	lonely.add_player(1, "Host")
	lonely.add_player(2, "Gone")
	lonely.start(1)
	_until(lonely, Party.Phase.PLAYING)
	lonely.submit(1, 1, 450, 500, "")
	lonely.remove_player(2)
	check(_until(lonely, Party.Phase.RESULTS, 3000), "round completes when the missing player leaves")

func _lobby_rules() -> void:
	var party := Party.new(1)
	for id in range(1, Party.MAX_PLAYERS + 1):
		check(party.add_player(id, "P"), "seat %d" % id)
	check(not party.add_player(99, "Extra"), "room is full at eight")
	check(not party.add_player(3, "Twin"), "no duplicate ids")
	party.remove_player(3)
	check(party.add_player(99, "Extra") and party.players[99].slot == 2, "freed colour is reused")
	check(Party.clean_name("[b]x[/b]<i>", 5) == "bx/bi", "markup characters are stripped from names")
	check(Party.clean_name("ThisNameIsFarTooLong", 5).length() == 12, "names are capped")
	check(Party.clean_name(42, 5) == "Player 5", "non-string names fall back")
	var before := party.roster_revision
	party.remove_player(1234)
	check(party.roster_revision == before, "removing a stranger changes nothing")

## The host's power level applies to everyone and is what the replay uses.
func _power() -> void:
	var party := Party.new(21)
	party.add_player(1, "Host")
	party.add_player(2, "Ada")
	check(not party.set_power(2, 2) and not party.set_power(1, 3) and not party.set_power(1, -1), "only the host picks a real power level")
	check(party.set_power(1, 2) and party.power == 2, "host picks MAXED")
	party.set_rounds(1, 1)
	party.start(1)
	check(not party.set_power(1, 0), "power is locked once the match starts")
	_until(party, Party.Phase.PLAYING)
	# A long log, as an upgraded flight can produce.
	var plan := "t20" + "d45".repeat(300)
	check(party.submit(1, 1, 450, 900, plan) and party.submit(2, 1, 450, 900, ""), "long input logs are accepted")
	check(_until(party, Party.Phase.RESULTS, 30000), "maxed flights still resolve")
	var maxed: Flight = Flight.replay(party.round_seed, 450, 900, Flight.decode_inputs(plan), Upgrades.preset(2))
	var stock: Flight = Flight.replay(party.round_seed, 450, 900, Flight.decode_inputs(plan))
	check(party.players[1].round_cm == maxed.distance_cm(), "the replay used the party's power level")
	check(maxed.distance_cm() > stock.distance_cm(), "and MAXED really is stronger than STOCK")
