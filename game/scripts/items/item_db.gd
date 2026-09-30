class_name ItemDB
extends RefCounted
## Equipment rules: random item generation, rarity, enhancement and prices.
## Items are plain Dictionaries so they save straight into the save file:
## { id, slot, name, rarity, ilvl, main: {stat: value}, bonus: {stat: value}, enhance }
## Stats: "ATK", "DEF", "HP" (flat) and "STR", "AGI", "INT", "VIT" (primary).

const SLOTS := ["weapon", "armor", "accessory"]
const SLOT_NAMES := {"weapon": "Senjata", "armor": "Armor", "accessory": "Aksesoris"}
const RARITY_NAMES := ["Biasa", "Magic", "Rare", "Epic"]
const RARITY_COLORS: Array[Color] = [Color(0.92, 0.92, 0.9), Color(0.45, 0.95, 0.45), Color(0.4, 0.65, 1.0), Color(0.78, 0.45, 1.0)]
## Main stat multiplier per rarity, and how many bonus lines it rolls.
const RARITY_MULT := [1.0, 1.15, 1.3, 1.5]
const RARITY_LINES := [0, 1, 2, 3]
## Base names by item level tier (Lv 1-6, 7-13, 14-20).
const NAMES := {
	"weapon": ["Pedang Besi", "Pedang Baja", "Pedang Ksatria"],
	"armor": ["Zirah Kulit", "Zirah Rantai", "Zirah Pelat"],
	"accessory": ["Cincin Tembaga", "Cincin Perak", "Cincin Emas"],
}
const PRIMARY := ["STR", "AGI", "INT", "VIT"]
const STAT_ORDER := ["ATK", "DEF", "HP", "STR", "AGI", "INT", "VIT"]
const MAX_ENHANCE := 5
## Chance to succeed when going to +1, +2, ... +5. A failure only costs the gold.
const ENHANCE_CHANCE := [1.0, 0.9, 0.75, 0.6, 0.45]
## Each enhancement level adds this share of the item's main stats.
const ENHANCE_STEP := 0.1


static func generate(slot: String, ilvl: int, rarity: int, rng: RandomNumberGenerator) -> Dictionary:
	ilvl = clampi(ilvl, 1, Progress.MAX_LEVEL)
	rarity = clampi(rarity, 0, RARITY_NAMES.size() - 1)
	var mult: float = RARITY_MULT[rarity] * rng.randf_range(0.9, 1.1)
	var main := {}
	match slot:
		"weapon":
			main["ATK"] = maxi(1, roundi((3.0 + ilvl * 1.5) * mult))
		"armor":
			main["DEF"] = maxi(1, roundi((2.0 + ilvl * 0.8) * mult))
			main["HP"] = maxi(1, roundi((20.0 + ilvl * 12.0) * mult))
		_:
			main[PRIMARY[rng.randi_range(0, PRIMARY.size() - 1)]] = maxi(1, roundi((1.0 + ilvl * 0.5) * mult))
	var bonus := {}
	var pool := PRIMARY.duplicate()
	for i in RARITY_LINES[rarity]:
		var stat: String = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		bonus[stat] = maxi(1, roundi((1.0 + ilvl * 0.35) * rng.randf_range(0.8, 1.2)))
	var tier := 0 if ilvl <= 6 else (1 if ilvl <= 13 else 2)
	return {"slot": slot, "name": NAMES[slot][tier], "rarity": rarity, "ilvl": ilvl,
			"main": main, "bonus": bonus, "enhance": 0}


## Random drop: slot, rarity (from `weights`) and an item level near `level`.
static func roll(level: int, weights: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for w in weights:
		total += float(w)
	var pick := rng.randf() * total
	var rarity := 0
	for i in weights.size():
		pick -= float(weights[i])
		if pick <= 0.0:
			rarity = i
			break
	var slot: String = SLOTS[rng.randi_range(0, SLOTS.size() - 1)]
	return generate(slot, level + rng.randi_range(-1, 1), rarity, rng)


## Final stats of an item: main stats grown by enhancement, plus bonus lines.
static func stats(item: Dictionary) -> Dictionary:
	var out := {}
	var grow := 1.0 + ENHANCE_STEP * int(item.get("enhance", 0))
	for stat in item.get("main", {}):
		out[stat] = roundi(float(item["main"][stat]) * grow)
	for stat in item.get("bonus", {}):
		out[stat] = int(out.get(stat, 0)) + int(item["bonus"][stat])
	return out


static func title(item: Dictionary) -> String:
	var e := int(item.get("enhance", 0))
	return ("+%d " % e if e > 0 else "") + String(item.get("name", "?"))


static func color(item: Dictionary) -> Color:
	return RARITY_COLORS[clampi(int(item.get("rarity", 0)), 0, RARITY_COLORS.size() - 1)]


static func enhance_cost(item: Dictionary) -> int:
	return roundi((30.0 + int(item["ilvl"]) * 10.0) * (int(item["enhance"]) + 1) * (1.0 + int(item["rarity"]) * 0.5))


## Chance for the next enhancement to succeed (0 when already at the maximum).
static func enhance_chance(item: Dictionary) -> float:
	var e := int(item["enhance"])
	return 0.0 if e >= MAX_ENHANCE else float(ENHANCE_CHANCE[e])


static func sell_price(item: Dictionary) -> int:
	return roundi((10.0 + int(item["ilvl"]) * 4.0) * (1.0 + int(item["rarity"])) * (1.0 + 0.3 * int(item["enhance"])))


## "ATK +12" lines in a fixed order.
static func stat_lines(item_stats: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for stat in STAT_ORDER:
		if item_stats.has(stat):
			lines.append("%s +%d" % [stat, int(item_stats[stat])])
	return lines
