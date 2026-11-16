extends SceneTree
## Plays through the real screens in a window and saves screenshots to
## build/shots/ for a human (or a vision model) to look at. Not part of CI.
##   godot --path . --resolution 1170x540 --script res://tests/render.gd

const Aim := preload("res://game/sim/aim.gd")
const Party := preload("res://game/sim/party.gd")
const Upgrades := preload("res://game/sim/upgrades.gd")

var main: Node
var folder := "res://build/shots/"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var prefix := "phone_" if root.size.x > root.size.y * 2 else ""
	main = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _wait(3.5)
	await _shot(prefix + "1_menu")

	# The shop, with enough stars to afford something, then a maxed cannon on a
	# wild course. The real profile is put back afterwards.
	var save: Node = root.get_node("Save")
	var kept := [save.stars, save.earned, save.levels.duplicate(), save.best_cm, save.launches]
	save.stars = 260
	save.levels = Upgrades.clean({"powder": 3, "rubber": 2, "springs": 1, "thrusters": 5})
	main._show_shop()
	await _wait(0.4)
	await _shot(prefix + "1b_shop")
	main._start_solo()
	main._begin_round(7, 0, Upgrades.preset(2))
	main._start_aim(0)
	await _wait(0.5)
	await _shot(prefix + "1c_wild_course")
	main.aim.force()
	main._fire()
	for index in 3:
		await _wait(2.5)
		main._on_primary()
		await _wait(0.2)
		await _shot(prefix + "1d_maxed_flight_%d" % index)
	var cap := 0
	while main.stage == main.Stage.FLYING and cap < 18000:
		cap += 1
		await physics_frame
	await _wait(0.6)
	await _shot(prefix + "1e_maxed_landed")
	save.stars = kept[0]
	save.earned = kept[1]
	save.levels = kept[2]
	save.best_cm = kept[3]
	save.launches = kept[4]
	save.store()

	main._start_solo()
	await _wait(0.4)
	await _shot(prefix + "2_pump")
	# Pump three times near the peak, then fire around 40 degrees.
	for pump in Aim.PUMPS:
		while main.aim.gauge < 0.93:
			await physics_frame
		main._on_primary()
	await _wait(0.15)
	await _shot(prefix + "3_angle")
	while absi(main.aim.angle_decideg - 400) > 12:
		await physics_frame
	main._on_primary()
	await _wait(0.12)
	await _shot(prefix + "4_fire")
	for index in 4:
		await _wait(1.3)
		if main.stage != main.Stage.FLYING:
			break
		if index == 1:
			main._on_primary()
			await _wait(0.1)
		await _shot(prefix + "5_flight_%d" % index)
	var limit := 0
	while main.stage == main.Stage.FLYING and limit < 3600:
		limit += 1
		await physics_frame
	await _wait(0.6)
	await _shot(prefix + "6_landed")

	# A one-player party exercises the lobby, countdown and score panels.
	main._show_menu()
	var session: Node = root.get_node("Session")
	session.player_name = "Matt"
	if session.host():
		session.party.add_player(7, "Ada")
		session.party.add_player(8, "Grace")
		main._show_lobby()
		await _wait(0.5)
		await _shot(prefix + "7_lobby")
		session.set_rounds(1)
		session.set_power(1)
		await _wait(0.3)
		await _shot(prefix + "7b_lobby_power")
		session.start_match()
		await _wait(1.2)
		await _shot(prefix + "8_countdown")
		while session.phase != Party.Phase.PLAYING:
			await physics_frame
		session.ghosts[7] = {"x": 30.0, "y": 9.0, "state": session.FLYING}
		session.ghosts[8] = {"x": 16.0, "y": 5.0, "state": session.FLYING}
		session.party.submit(7, 1, 450, 800, "t30")
		session.party.submit(8, 1, 300, 600, "")
		await _wait(0.5)
		main.aim.force()
		main._fire()
		await _wait(1.0)
		session.ghosts[7] = {"x": 30.0, "y": 9.0, "state": session.FLYING}
		session.ghosts[8] = {"x": 16.0, "y": 5.0, "state": session.FLYING}
		await _wait(0.3)
		await _shot(prefix + "9_party_flight")
		limit = 0
		while session.phase != Party.Phase.RESULTS and limit < 4000:
			limit += 1
			await physics_frame
		await _wait(0.6)
		await _shot(prefix + "10_round_results")
		session.advance()
		await _wait(0.8)
		await _shot(prefix + "11_final")
		session.leave()
	print("RENDER_DONE")
	quit()

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder + name + ".png")
