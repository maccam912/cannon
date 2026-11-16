extends RefCounted
## Progression: what can be bought with stars, what it costs, and how many
## stars a launch pays. Levels are plain integers that Flight and Course read,
## so an upgraded flight is exactly as replayable as a stock one.

const IDS := ["powder", "rubber", "springs", "farm", "thrusters", "slipstream", "luck"]

const INFO := {
	"powder": {"name": "Gunpowder", "blurb": "The cannon fires harder.", "max": 10, "cost": 15},
	"rubber": {"name": "Rubber Suit", "blurb": "Keep more bounce and speed on every landing.", "max": 10, "cost": 15},
	"springs": {"name": "Super Springs", "blurb": "Springs fling you higher and faster.", "max": 10, "cost": 20},
	"farm": {"name": "Spring Farm", "blurb": "More springs grow on the course, some over hazards.", "max": 10, "cost": 25},
	"thrusters": {"name": "Thrusters", "blurb": "One more thrust charge per level.", "max": 5, "cost": 40},
	"slipstream": {"name": "Slipstream", "blurb": "Less drag, so speed lasts longer.", "max": 10, "cost": 20},
	"luck": {"name": "Lucky Charm", "blurb": "Wild courses turn up more often.", "max": 10, "cost": 30},
}

## Each level costs about half as much again as the one before.
const GROWTH_NUMERATOR := 31
const GROWTH_DENOMINATOR := 20

## Party power levels the host can pick; everyone gets the same one.
const PRESET_NAMES := ["STOCK", "BOOSTED", "MAXED"]

static func max_level(id: String) -> int:
	return int(INFO[id].max)

## Price of going from `level` to `level + 1`.
static func cost(id: String, level: int) -> int:
	var price := int(INFO[id].cost) * 1000
	for _i in level:
		price = price * GROWTH_NUMERATOR / GROWTH_DENOMINATOR
	return (price + 500) / 1000

## Any input becomes a full, in-range set of levels.
static func clean(levels: Variant) -> Dictionary:
	var out: Dictionary = {}
	for id: String in IDS:
		var value: Variant = levels.get(id, 0) if levels is Dictionary else 0
		out[id] = clampi(int(value), 0, max_level(id)) if (value is int or value is float) and is_finite(float(value)) else 0
	return out

static func preset(index: int) -> Dictionary:
	var out: Dictionary = {}
	for id: String in IDS:
		out[id] = max_level(id) * clampi(index, 0, 2) / 2
	return out

## Stars paid for one launch: a star per ten metres, three per coin, and a
## tip for perfect pressure.
static func stars(distance_cm: int, coins: int, perfect: bool) -> int:
	return maxi(distance_cm, 0) / 1000 + coins * 3 + (10 if perfect else 0)

static func effect(id: String, level: int) -> String:
	match id:
		"powder":
			return "+%d%% launch speed" % (level * 8)
		"rubber":
			return "+%d%% bounce" % (level * 3)
		"springs":
			return "+%d%% spring power" % (level * 8)
		"farm":
			return "+%d%% spring chance" % (level * 5)
		"thrusters":
			return "%d thrusts" % (3 + level)
		"slipstream":
			return "-%d%% drag" % (level * 6)
		"luck":
			return "%d%% wild courses" % (6 + level * 2)
	return ""
