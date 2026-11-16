extends Node
## Game flow: menu, solo launches and party rounds. Owns the local Aim and
## Flight, feeds the world and HUD, and talks to Session in party mode.

const Aim := preload("res://game/sim/aim.gd")
const Flight := preload("res://game/sim/flight.gd")
const Party := preload("res://game/sim/party.gd")
const Style := preload("res://game/ui/style.gd")
const World := preload("res://game/world.gd")
const Hud := preload("res://game/hud.gd")
const Menu := preload("res://game/ui/menu.gd")
const Lobby := preload("res://game/ui/lobby.gd")
const Shop := preload("res://game/ui/shop.gd")
const Course := preload("res://game/sim/course.gd")
const Upgrades := preload("res://game/sim/upgrades.gd")

enum Mode { MENU, LOBBY, SOLO, PARTY }
enum Stage { IDLE, COUNTDOWN, AIMING, FLYING, LANDED, WATCHING }

var mode := Mode.MENU
var stage := Stage.IDLE
var world: World
var hud: Hud
var menu: Menu
var lobby: Lobby
var shop: Shop
## Upgrade levels in force for the current launch: your own in solo, the
## host's preset in a party.
var levels: Dictionary = {}

var aim: Aim
var flight: Flight
var course_seed := 1
var slot := 0
var input_log: Array = []
var _pending := 0
var _from := Vector2.ZERO      # previous tick position, for smooth drawing
var _aim_ticks_left := 0
var _countdown_shown := -1
var _demo_wait := 0
var _quitting := false
var _landed_at := 0
var _final_announced := false
var _watching := ""
var _connecting := false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	world = World.new()
	add_child(world)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	menu = Menu.new()
	layer.add_child(menu)
	lobby = Lobby.new()
	layer.add_child(lobby)
	shop = Shop.new()
	layer.add_child(shop)
	shop.back_pressed.connect(_show_menu)
	shop.launch_pressed.connect(_start_solo)
	menu.upgrades_pressed.connect(_show_shop)
	hud.primary.connect(_on_primary)
	hud.secondary.connect(_on_secondary)
	hud.menu_pressed.connect(_leave_to_menu)
	menu.solo_pressed.connect(_start_solo)
	menu.host_pressed.connect(_host_party)
	menu.join_pressed.connect(_join_party)
	lobby.leave_pressed.connect(_leave_to_menu)
	Session.phase_changed.connect(_on_phase_changed)
	Session.roster_changed.connect(_on_roster_changed)
	Session.status_changed.connect(menu.set_status)
	Session.session_closed.connect(_on_session_closed)
	_show_menu()
	var args := OS.get_cmdline_user_args()
	if "--native-smoke" in args:
		_native_smoke()
	elif "--solo" in args:
		_start_solo()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if mode == Mode.MENU:
			_quit()
		else:
			_leave_to_menu()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and event is InputEventKey:
		if event.physical_keycode == KEY_F11:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif event.physical_keycode == KEY_ESCAPE and mode != Mode.MENU:
			_leave_to_menu()

# --- Screens -------------------------------------------------------------------

func _show(screen: Control) -> void:
	menu.visible = screen == menu
	lobby.visible = screen == lobby
	hud.visible = screen == hud
	shop.visible = screen == shop

func _show_menu() -> void:
	mode = Mode.MENU
	stage = Stage.IDLE
	flight = null
	aim = null
	menu.refresh()
	menu.set_busy(false)
	_show(menu)
	Sfx.music("music_menu")
	world.muted = true
	_demo_wait = 30

func _leave_to_menu() -> void:
	if Session.role != "offline":
		Session.leave()   # session_closed brings the menu back
	else:
		_show_menu()

func _on_session_closed() -> void:
	if mode in [Mode.LOBBY, Mode.PARTY]:
		_show_menu()

func _quit() -> void:
	if _quitting:
		return
	_quitting = true
	Session.leave()
	# Give the join code a moment to be revoked.
	await get_tree().create_timer(0.4).timeout
	get_tree().quit()

# --- Solo ------------------------------------------------------------------------

func _start_solo() -> void:
	mode = Mode.SOLO
	_show(hud)
	Sfx.music("music_flight")
	_begin_round(randi(), 0, Save.levels)
	if world.course.event == Course.Event.NONE:
		hud.set_info("BEST  " + Style.meters(Save.best_cm) if Save.best_cm > 0 else "")
	_start_aim(0)

## The shop sits over the menu's demo flights; mode stays MENU underneath.
func _show_shop() -> void:
	if mode != Mode.MENU:
		_show_menu()
	shop.refresh()
	_show(shop)

# --- Party -----------------------------------------------------------------------

func _host_party() -> void:
	if _connecting:
		return
	_connecting = true
	Session.player_name = menu.player_name()
	menu.set_busy(true)
	menu.set_status("Starting a party...")
	await Rooms.host()
	_connecting = false
	menu.set_busy(false)
	if Session.is_host() and mode == Mode.MENU:
		_show_lobby()

func _join_party(code: String) -> void:
	if _connecting:
		return
	_connecting = true
	Session.player_name = menu.player_name()
	menu.set_busy(true)
	await Rooms.join(code)
	_connecting = false
	menu.set_busy(false)
	# The lobby opens when the host's first phase message arrives.

func _show_lobby() -> void:
	mode = Mode.LOBBY
	stage = Stage.IDLE
	_show(lobby)
	lobby.refresh()
	Sfx.music("music_menu")
	world.muted = true

func _on_phase_changed() -> void:
	if not Session.connected():
		return
	match Session.phase:
		Party.Phase.LOBBY:
			_show_lobby()
		Party.Phase.COUNTDOWN:
			_enter_party_round()
			stage = Stage.COUNTDOWN
			_countdown_shown = -1
		Party.Phase.PLAYING:
			if mode != Mode.PARTY or stage != Stage.COUNTDOWN:
				_enter_party_round()
			if Session.entry(Session.local_id).get("playing", false):
				hud.show_banner("GO!", "", 0.7, Style.ORANGE)
				Sfx.play("go")
				_start_aim(Party.AIM_TICKS)
			else:
				stage = Stage.WATCHING
				hud.show_banner("", "Round in progress - you are in the next one")
		Party.Phase.RESULTS:
			_show_party_results(false)
		Party.Phase.FINAL:
			_show_party_results(true)

func _enter_party_round() -> void:
	mode = Mode.PARTY
	_final_announced = false
	_show(hud)
	Sfx.music("music_flight")
	_begin_round(Session.round_seed, int(Session.entry(Session.local_id).get("slot", 0)), Upgrades.preset(Session.power))
	hud.set_info("ROUND %d OF %d" % [Session.round_number, Session.rounds])

func _on_roster_changed() -> void:
	# The final table is a snapshot: players leaving afterwards stay on it.
	if mode == Mode.PARTY and hud.result_visible() and Session.phase == Party.Phase.RESULTS:
		_show_party_results(false)

func _show_party_results(final: bool) -> void:
	if mode != Mode.PARTY:
		_enter_party_round()
	stage = Stage.LANDED
	hud.flying = false
	hud.show_aim(null)
	hud.show_banner("")
	var rows: Array = []
	var ranked := Session.standings() if final else Session.roster.duplicate()
	if not final:
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.round_cm > b.round_cm if a.round_cm != b.round_cm else a.id < b.id)
	for row: Dictionary in ranked:
		rows.append({"slot": row.slot, "name": row.name, "me": row.id == Session.local_id,
				"text": Style.meters(row.total_cm) if final else (Style.meters(row.round_cm) if row.round_cm >= 0 else "-"),
				"note": "best " + Style.meters(row.best_cm) if final else "total " + Style.meters(row.total_cm)})
	var buttons: Array = []
	var last := Session.round_number >= Session.rounds
	if Session.is_host():
		if final:
			buttons.append(["LOBBY", Style.ORANGE, Session.advance])
		else:
			buttons.append(["FINAL SCORES" if last else "NEXT ROUND", Style.ORANGE, Session.advance])
	else:
		buttons.append(["LEAVE", Style.SLATE, _leave_to_menu])
	if final:
		var winner: Dictionary = ranked[0] if not ranked.is_empty() else {}
		var mine: bool = not winner.is_empty() and winner.id == Session.local_id
		hud.show_result("YOU WIN!" if mine else "%s WINS!" % str(winner.get("name", "Nobody")).to_upper(), "", "Total distance over %d round%s" % [Session.rounds, "" if Session.rounds == 1 else "s"], rows, buttons)
		if not _final_announced:
			_final_announced = true
			Sfx.play("fanfare")
	else:
		hud.show_result("ROUND %d OF %d" % [Session.round_number, Session.rounds], "", "" if Session.is_host() else "The host starts the next round", rows, buttons, Style.BLUE)

# --- One launch ----------------------------------------------------------------

func _begin_round(new_seed: int, new_slot: int, new_levels: Dictionary) -> void:
	course_seed = new_seed
	slot = new_slot
	levels = Upgrades.clean(new_levels)
	flight = null
	aim = null
	input_log = []
	_pending = 0
	_watching = ""
	stage = Stage.IDLE
	world.muted = false
	world.setup(course_seed, slot, levels)
	world.set_aim(45.0, 0.0)
	hud.reset()
	hud.base_thrusts = Flight.START_THRUSTS + int(levels.thrusters)
	hud.max_thrusts = hud.base_thrusts + Flight.SPARE_THRUSTS

func _start_aim(deadline_ticks: int) -> void:
	aim = Aim.new()
	_aim_ticks_left = deadline_ticks
	stage = Stage.AIMING
	hud.show_aim(aim)
	# A wild course announces itself before you pump.
	var event: int = world.course.event
	if event != Course.Event.NONE:
		hud.show_banner(Course.EVENT_NAMES[event], Course.EVENT_BLURBS[event], 2.4, Color(1.0, 0.85, 0.3))
		hud.set_info(Course.EVENT_NAMES[event])
		Sfx.play("perfect")

func _on_primary() -> void:
	if stage == Stage.AIMING:
		var result := aim.tap()
		if result.get("kind") == "pump":
			Sfx.play("pump", 0.8 + float(result.score) * 0.5)
			world.shake(4.0 + float(result.score) * 8.0)
			if result.perfect:
				Sfx.play("perfect", 1.0, -6.0)
				world.popup(0.0, Flight.MUZZLE_Y + 3.5, "PERFECT!", Color(1.0, 0.85, 0.3))
		elif result.get("kind") == "fire":
			_fire()
	elif stage == Stage.FLYING:
		_pending |= Flight.IN_THRUST
	elif stage == Stage.LANDED and mode == Mode.SOLO and Time.get_ticks_msec() - _landed_at > 1200:
		# Tap anywhere to go again, once the result has had a moment to register.
		_start_solo()

func _on_secondary() -> void:
	if stage == Stage.FLYING:
		_pending |= Flight.IN_DIVE
	elif stage == Stage.AIMING:
		_on_primary()

func _fire() -> void:
	flight = Flight.new(course_seed, levels)
	flight.launch(aim.angle_decideg, aim.power_permille)
	_from = Vector2(flight.x, flight.y)
	input_log = []
	_pending = 0
	stage = Stage.FLYING
	hud.flying = true
	hud.show_aim(null)
	world.set_aim(aim.angle_decideg / 10.0, 0.0)
	world.fire()
	Sfx.play("fire")
	if flight.perfect:
		hud.show_banner("PERFECT LAUNCH!", "", 1.0, Color(1.0, 0.85, 0.3))

func _landed() -> void:
	stage = Stage.LANDED
	_landed_at = Time.get_ticks_msec()
	hud.flying = false
	var distance := flight.distance_cm()
	var stars := Upgrades.stars(distance, flight.coins, flight.perfect)
	Save.award(stars)
	if mode == Mode.SOLO:
		var is_best := Save.record(distance)
		if is_best:
			Sfx.play("fanfare")
		hud.show_result("NEW BEST!" if is_best else "TOUCHDOWN", Style.meters(distance),
				"+%d stars  -  you have %d  -  best %s" % [stars, Save.stars, Style.meters(Save.best_cm)],
				[], [["MENU", Style.SLATE, _show_menu], ["UPGRADE!" if Save.can_buy_any() else "UPGRADES", Style.GREEN if Save.can_buy_any() else Style.PURPLE, _show_shop],
				["LAUNCH AGAIN", Style.ORANGE, _start_solo]],
				Color(1.0, 0.85, 0.3) if is_best else Style.ORANGE)
	elif mode == Mode.PARTY:
		Session.submit(aim.angle_decideg, aim.power_permille, Flight.encode_inputs(input_log))
		Session.report(flight.x, 0.0, Session.LANDED)
		hud.show_banner(Style.meters(distance), "+%d stars  -  waiting for the others to land" % stars)

func _physics_process(_delta: float) -> void:
	if mode == Mode.MENU or mode == Mode.LOBBY:
		_demo_tick()
		return
	match stage:
		Stage.AIMING:
			aim.advance()
			if mode == Mode.PARTY:
				Session.report(0.0, Flight.MUZZLE_Y, Session.AIMING)
				_aim_ticks_left -= 1
				if _aim_ticks_left <= 0:
					aim.force()
					_fire()
		Stage.FLYING:
			_from = Vector2(flight.x, flight.y)
			if input_log.size() >= Flight.MAX_INPUTS:
				_pending = 0
			var at := flight.tick
			var applied := flight.step(_pending)
			_pending = 0
			if applied != 0:
				input_log.append([at, applied])
				hud.flash_hint("thrust" if applied == Flight.IN_THRUST else "dive")
			for event: Dictionary in flight.events:
				world.handle_event(event)
			flight.events.clear()
			if mode == Mode.PARTY:
				Session.report(flight.x, flight.y, Session.FLYING)
			if flight.done:
				_landed()

## Behind the menu a bot keeps launching, so the title screen shows the game.
func _demo_tick() -> void:
	if flight == null or flight.done:
		_demo_wait -= 1
		if _demo_wait > 0:
			return
		_demo_wait = 120
		course_seed = randi()
		world.setup(course_seed, randi() % 5, Save.levels)
		world.set_aim(42.0, 0.0)
		flight = Flight.new(course_seed, Save.levels)
		flight.launch(380 + randi() % 120, 700 + randi() % 300)
		_from = Vector2(flight.x, flight.y)
		world.fire()
		return
	_from = Vector2(flight.x, flight.y)
	var want := 0
	if flight.y < 1.0 and flight.vy <= 0.0 and flight.vx < 16.0:
		want = Flight.IN_THRUST
	flight.step(want)
	for event: Dictionary in flight.events:
		world.handle_event(event)
	flight.events.clear()

func _process(delta: float) -> void:
	if stage == Stage.AIMING and aim != null:
		world.set_aim(aim.angle_decideg / 10.0 if aim.stage != Aim.Stage.PUMP else 45.0, aim.pressure() + (aim.gauge * 0.25 if aim.stage == Aim.Stage.PUMP else 0.0))
	if flight != null and (stage in [Stage.FLYING, Stage.LANDED] or mode in [Mode.MENU, Mode.LOBBY]):
		var blend := Engine.get_physics_interpolation_fraction() if not flight.done else 1.0
		var at := _from.lerp(Vector2(flight.x, flight.y), blend)
		world.show_hero(at.x, at.y, flight.vx, flight.vy, flight.rolling, flight.diving, delta)
		if mode in [Mode.SOLO, Mode.PARTY]:
			hud.set_flight(at.x, at.y, flight.vx, flight.thrusts)
	if mode != Mode.PARTY:
		return
	if stage == Stage.COUNTDOWN:
		var seconds := int(ceil(Session.seconds_left()))
		if seconds != _countdown_shown and seconds > 0:
			_countdown_shown = seconds
			hud.show_banner(str(seconds), "Same course for everyone - furthest flight wins")
			Sfx.play("tick")
	elif stage == Stage.AIMING:
		hud.set_info("ROUND %d OF %d  -  FIRE IN %d" % [Session.round_number, Session.rounds, int(ceil(_aim_ticks_left / 60.0))])
	else:
		hud.set_info("ROUND %d OF %d" % [Session.round_number, Session.rounds])
	_update_party_view()

func _update_party_view() -> void:
	var ghosts: Array = []
	var board: Array = []
	for row: Dictionary in Session.roster:
		var me: bool = row.id == Session.local_id
		var ghost: Dictionary = Session.ghosts.get(row.id, {})
		var distance := 0.0
		if row.round_cm >= 0:
			distance = row.round_cm / 100.0
		elif me and flight != null:
			distance = flight.x
		elif not ghost.is_empty():
			distance = ghost.x
		if not me and not ghost.is_empty():
			ghosts.append({"id": row.id, "slot": row.slot, "name": row.name, "x": ghost.x, "y": ghost.y, "state": ghost.state})
		if row.playing:
			var landed: bool = row.round_cm >= 0 or (not ghost.is_empty() and ghost.state == Session.LANDED)
			board.append({"name": row.name, "slot": row.slot, "me": me, "distance": distance,
					"text": "%d m%s" % [int(distance), "" if landed else " >"]})
	board.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance > b.distance)
	# Once you are down (or sitting a round out), follow whoever is furthest
	# ahead and still in the air.
	if stage in [Stage.LANDED, Stage.WATCHING] and Session.phase == Party.Phase.PLAYING and Time.get_ticks_msec() - _landed_at > 1500:
		var leader: Dictionary = {}
		for ghost: Dictionary in ghosts:
			if ghost.state == Session.FLYING and (leader.is_empty() or ghost.x > leader.x):
				leader = ghost
		if not leader.is_empty():
			world.watch(leader.x, leader.y, 20.0)
			if _watching != leader.name:
				_watching = leader.name
				hud.show_banner("" if flight == null else Style.meters(flight.distance_cm()), "Watching %s" % leader.name)
	world.set_ghosts(ghosts)
	hud.set_board(board if Session.phase == Party.Phase.PLAYING else [])

func _native_smoke() -> void:
	if not Session.host():
		push_error("Native extension did not start an Iroh host")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.25).timeout
	Session.leave()
	await get_tree().create_timer(0.25).timeout
	print("NATIVE_RUNTIME_PASS")
	get_tree().quit()
