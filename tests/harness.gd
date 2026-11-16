extends SceneTree
## Minimal test base: subclasses implement run() and call check().

var failures := 0

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	await run()
	if failures > 0:
		print("TEST FAIL: %d check(s) failed" % failures)
		quit(1)
	else:
		print(label() + "_PASS")
		quit()

func run() -> void:
	pass

func label() -> String:
	return "TEST"

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("TEST FAIL: " + message)
