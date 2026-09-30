class_name ItemDB
extends RefCounted
## Equipment rules: random item generation, rarity, enhancement and prices.
## Items are plain Dictionaries so they save straight into the save file:
## { id, slot, name, rarity, ilvl, main: {stat: value}, bonus: {stat: value}, enhance }
## Stats: "ATK", "DEF", "HP" (flat) and "STR", "AGI", "INT", "VIT" (primary).

## Item types (what drops). The two ring slots both take "accessory" items.
const SLOTS := ["weapon", "helmet", "armor", "gloves", "legs", "boots", "necklace", "accessory"]
## Equipment slots, in the order the windows show them.
const EQUIP_SLOTS := ["weapon", "helmet", "armor", "gloves", "legs", "boots", "necklace", "accessory", "accessory_2"]
const SLOT_NAMES := {
	"weapon": "Senjata", "helmet": "Helm", "armor": "Badan", "gloves": "Sarung Tangan", "legs": "Celana",
	"boots": "Sepatu", "necklace": "Kalung", "accessory": "Cincin", "accessory_2": "Cincin 2",
}
const RARITY_NAMES := ["Biasa", "Magic", "Rare", "Epic"]
## Dragon Nest colours: Normal white, Magic blue, Rare yellow, Epic purple.
const RARITY_COLORS: Array[Color] = [Color(0.92, 0.92, 0.9), Color(0.35, 0.62, 1.0), Color(1.0, 0.8, 0.25), Color(0.76, 0.42, 1.0)]
## Main stat multiplier per rarity, and how many bonus lines it rolls.
const RARITY_MULT := [1.0, 1.15, 1.3, 1.5]
const RARITY_LINES := [0, 1, 2, 3]
## Base names by item level tier (Lv 1-6, 7-13, 14-20).
const NAMES := {
	"weapon": ["Pedang Besi", "Pedang Baja", "Pedang Ksatria"],
	"helmet": ["Tudung Kulit", "Helm Rantai", "Helm Pelat"],
	"armor": ["Zirah Kulit", "Zirah Rantai", "Zirah Pelat"],
	"gloves": ["Sarung Tangan Kulit", "Sarung Tangan Rantai", "Gauntlet Pelat"],
	"legs": ["Celana Kulit", "Celana Rantai", "Pelindung Kaki Pelat"],
	"boots": ["Sepatu Kulit", "Sepatu Rantai", "Sepatu Pelat"],
	"necklace": ["Kalung Tembaga", "Kalung Perak", "Kalung Emas"],
	"accessory": ["Cincin Tembaga", "Cincin Perak", "Cincin Emas"],
}
## Icon file per type, one for each tier (assets/ui/items/<name>.png). Swords and
## necklaces are renders made with tests/bake_item_icons.gd; armor and rings are painted icons.
const TIER_ICONS := {
	"weapon": ["sword_iron", "sword_steel", "sword_knight"],
	"helmet": ["helmet_leather", "helmet_chain", "helmet_plate"],
	"armor": ["armor_leather", "armor_chain", "armor_plate"],
	"gloves": ["gloves_leather", "gloves_chain", "gloves_plate"],
	"legs": ["legs_leather", "legs_chain", "legs_plate"],
	"boots": ["boots_leather", "boots_chain", "boots_plate"],
	"necklace": ["necklace_copper", "necklace_silver", "necklace_gold"],
	"accessory": ["ring_copper", "ring_silver", "ring_gold"],
}
## Share of the body armor's DEF / HP that each armor part gives.
const ARMOR_SHARE := {"armor": [1.0, 1.0], "helmet": [0.5, 0.5], "legs": [0.6, 0.6], "gloves": [0.35, 0.0], "boots": [0.35, 0.3]}
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
		"armor", "helmet", "legs", "gloves", "boots":
			var share: Array = ARMOR_SHARE[slot]
			main["DEF"] = maxi(1, roundi((2.0 + ilvl * 0.8) * mult * float(share[0])))
			if float(share[1]) > 0.0:
				main["HP"] = maxi(1, roundi((20.0 + ilvl * 12.0) * mult * float(share[1])))
			if slot == "gloves":
				main["ATK"] = maxi(1, roundi((1.0 + ilvl * 0.4) * mult))
		"necklace":
			main["HP"] = maxi(1, roundi((10.0 + ilvl * 8.0) * mult))
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


## Icon of an item, or of an empty equipment `slot` (drawn faint by the windows).
static func icon(item: Dictionary, slot := "") -> Texture2D:
	var kind := item_type(String(item.get("slot", slot)))
	if not TIER_ICONS.has(kind):
		return null
	var tier := maxi(0, (NAMES[kind] as Array).find(item.get("name", "")))
	return load("res://assets/ui/items/%s.png" % TIER_ICONS[kind][tier])


## Item type an equipment slot takes ("accessory_2" takes rings too).
static func item_type(slot: String) -> String:
	return "accessory" if slot == "accessory_2" else slot


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
