extends Node
## Small local profile: name, best launch, stars, upgrades. No accounts.

const Upgrades := preload("res://game/sim/upgrades.gd")
const PATH := "user://profile.json"

var player_name := ""
var best_cm := 0
var launches := 0
var muted := false
var stars := 0
var earned := 0
var levels: Dictionary = Upgrades.clean(null)

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
	if data.get("stars") is float:
		stars = maxi(int(data.stars), 0)
	if data.get("earned") is float:
		earned = maxi(int(data.earned), 0)
	levels = Upgrades.clean(data.get("levels"))

func store() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"name": player_name, "best_cm": best_cm, "launches": launches, "muted": muted,
				"stars": stars, "earned": earned, "levels": levels}))

## Returns true when this launch is a new personal best.
func record(distance_cm: int) -> bool:
	launches += 1
	var is_best := distance_cm > best_cm
	if is_best:
		best_cm = distance_cm
	store()
	return is_best

func award(amount: int) -> void:
	stars += maxi(amount, 0)
	earned += maxi(amount, 0)
	store()

func price(id: String) -> int:
	return Upgrades.cost(id, levels[id])

func can_buy(id: String) -> bool:
	return levels[id] < Upgrades.max_level(id) and stars >= price(id)

func can_buy_any() -> bool:
	for id: String in Upgrades.IDS:
		if can_buy(id):
			return true
	return false

func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	stars -= price(id)
	levels[id] += 1
	store()
	return true
