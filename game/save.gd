extends Node
## Small local profile: name, best launch, sound preference. No accounts.

const PATH := "user://profile.json"

var player_name := ""
var best_cm := 0
var launches := 0
var muted := false

func _ready() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(PATH)) != OK or not parser.data is Dictionary:
		return
	var data: Dictionary = parser.data
	if data.get("name") is String:
		player_name = str(data.name).left(12)
	if data.get("best_cm") is float:
		best_cm = maxi(int(data.best_cm), 0)
	if data.get("launches") is float:
		launches = maxi(int(data.launches), 0)
	muted = data.get("muted") == true

func store() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"name": player_name, "best_cm": best_cm, "launches": launches, "muted": muted}))

## Returns true when this launch is a new personal best.
func record(distance_cm: int) -> bool:
	launches += 1
	var is_best := distance_cm > best_cm
	if is_best:
		best_cm = distance_cm
	store()
	return is_best
