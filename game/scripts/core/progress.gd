extends Node
## Autoload "Progress": the character's level, EXP and gold, saved to
## user://save.cfg. Also turns the class's STR / AGI / INT / VIT into the
## combat numbers (HP, MP, ATK, DEF, crit) for the current level.

signal changed
signal leveled_up(level: int)

const FILE := "user://save.cfg"
const MAX_LEVEL := 20
const PRIMARY := ["STR", "AGI", "INT", "VIT"]
## [name, dungeon level]. Clearing a difficulty unlocks the next one. The dungeon
## level sets how strong enemies are, how much EXP they give and the item level of drops.
const DIFFICULTIES := [["Easy", 1], ["Normal", 7], ["Hard", 13], ["Master", 20]]
## Enemy growth per dungeon level above 1.
const ENEMY_HP_GROWTH := 0.3
const ENEMY_ATK_GROWTH := 0.2
const ENEMY_DEF_GROWTH := 1.5
const ENEMY_EXP_GROWTH := 0.3
## Player levels above the dungeon level before its EXP drops to a quarter.
const EXP_LEVEL_GAP := 5

var level := 1
## EXP collected toward the next level.
var experience := 0
var gold := 0
## Chosen difficulty (index into DIFFICULTIES) and the hardest one unlocked so far.
var difficulty := 0
var unlocked := 0

var _path := FILE
var _saving := true


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	# Tests always start a fresh Lv 1 character and never touch the player's save.
	_saving = not ("--smoke-test" in args or "--fps-probe" in args or "--key-selftest" in args)
	if _saving:
		load_file()


## EXP needed to go from `lv` to `lv + 1` (0 at the level cap).
static func exp_to_next(lv: int) -> int:
	if lv >= MAX_LEVEL:
		return 0
	return roundi(60.0 + 40.0 * pow(lv, 1.3))


func add_exp(amount: int) -> void:
	if level >= MAX_LEVEL or amount <= 0:
		return
	experience += amount
	var gained: Array[int] = []
	while level < MAX_LEVEL and experience >= exp_to_next(level):
		experience -= exp_to_next(level)
		level += 1
		gained.append(level)
	if level >= MAX_LEVEL:
		experience = 0
	save_file()
	for lv in gained:
		leveled_up.emit(lv)
	changed.emit()


## STR / AGI / INT / VIT of `stats`' class at the current level, plus what the
## equipped items add (unless `with_gear` is false).
func primary(stats: PlayerStats, with_gear := true) -> Dictionary:
	var up := float(level - 1)
	var out := {
		"STR": stats.base_str + stats.growth_str * up,
		"AGI": stats.base_agi + stats.growth_agi * up,
		"INT": stats.base_int + stats.growth_int * up,
		"VIT": stats.base_vit + stats.growth_vit * up,
	}
	if with_gear:
		var gear := Inventory.equipped_stats()
		for key in PRIMARY:
			out[key] += float(gear.get(key, 0))
	return out


## Writes the combat numbers for the current level and gear into `stats` (the
## player's own copy of its class). A Lv 1 Warrior without gear gets HP 500,
## MP 100, ATK 22, DEF 5, crit 15%.
func apply_to(stats: PlayerStats) -> void:
	var p := primary(stats)
	var gear := Inventory.equipped_stats()
	stats.attack_power = 2.0 + p["STR"] + float(gear.get("ATK", 0))
	stats.crit_chance = p["AGI"] / (p["AGI"] + 57.0)
	stats.max_mana = 60.0 + p["INT"] * 5.0
	stats.mana_regen = 3.0 + p["INT"] * 0.25
	stats.max_hp = 180.0 + p["VIT"] * 20.0 + float(gear.get("HP", 0))
	stats.defense = p["VIT"] * 0.5 - 3.0 + float(gear.get("DEF", 0))
	# Passive skills.
	for skill in skills_for(stats):
		var lv := skill_level(skill)
		if skill.kind != SkillData.Kind.PASSIVE or lv <= 0:
			continue
		var v := skill.passive_at(lv)
		match skill.passive_stat:
			"HP%":
				stats.max_hp *= 1.0 + v
			"DEF%":
				stats.defense *= 1.0 + v
			"CRIT":
				stats.crit_chance += v
			"MP_REGEN%":
				stats.mana_regen *= 1.0 + v


# --- Skills (SP, levels, quickslots) ------------------------------------------------

## SP earned per character level (Lv 1 already gives one batch).
const SP_PER_LEVEL := 3
## Input actions of the 10 quickslots, keys 1-0 by default.
const QUICKSLOT_ACTIONS: Array[StringName] = [&"skill_1", &"skill_2", &"potion_hp", &"potion_mp",
		&"quickslot_5", &"quickslot_6", &"quickslot_7", &"quickslot_8", &"quickslot_9", &"quickslot_0"]
## A quickslot holds "skill:<id>", "potion_hp", "potion_mp" or "" (empty).
const DEFAULT_QUICKSLOTS := ["skill:dash", "skill:whirl", "potion_hp", "potion_mp", "", "", "", "", "", ""]

## Skill id -> level the player has raised it to (default skills count as at least 1).
var skill_levels := {}
var quickslots: Array = DEFAULT_QUICKSLOTS.duplicate()
var _skill_cache := {}


## Every skill of the class (data/skills/<class>/*.tres), in grid order.
func skills_for(stats: PlayerStats) -> Array[SkillData]:
	if _skill_cache.has(stats.skill_dir):
		return _skill_cache[stats.skill_dir]
	var out: Array[SkillData] = []
	for file in ResourceLoader.list_directory(stats.skill_dir):
		if file.ends_with(".tres"):
			var s := load(stats.skill_dir.path_join(file)) as SkillData
			if s:
				out.append(s)
	out.sort_custom(func(a: SkillData, b: SkillData) -> bool:
		return a.grid_pos.y < b.grid_pos.y or (a.grid_pos.y == b.grid_pos.y and a.grid_pos.x < b.grid_pos.x))
	_skill_cache[stats.skill_dir] = out
	return out


func find_skill(stats: PlayerStats, id: StringName) -> SkillData:
	for s in skills_for(stats):
		if s.id == id:
			return s
	return null


func skill_level(skill: SkillData) -> int:
	var lv := int(skill_levels.get(String(skill.id), 0))
	return maxi(lv, 1) if skill.default_skill else lv


func sp_total() -> int:
	return SP_PER_LEVEL * level


func sp_spent(stats: PlayerStats) -> int:
	var spent := 0
	for skill in skills_for(stats):
		var start := 2 if skill.default_skill else 1  # a default skill's Lv 1 is free
		for lv in range(start, skill_level(skill) + 1):
			spent += skill.sp_cost(lv)
	return spent


func sp_left(stats: PlayerStats) -> int:
	return sp_total() - sp_spent(stats)


## Why the skill cannot go up a level right now ("" when it can).
func raise_blocker(stats: PlayerStats, skill: SkillData) -> String:
	var next := skill_level(skill) + 1
	if next > skill.max_level:
		return "Level maksimal"
	if level < skill.level_needed(next):
		return "Butuh Lv karakter %d" % skill.level_needed(next)
	if skill.requires != &"":
		var req := find_skill(stats, skill.requires)
		if req and skill_level(req) < skill.requires_level:
			return "Butuh %s Lv %d" % [req.display_name, skill.requires_level]
	if sp_left(stats) < skill.sp_cost(next):
		return "SP kurang (butuh %d)" % skill.sp_cost(next)
	return ""


func raise_skill(stats: PlayerStats, skill: SkillData) -> bool:
	if raise_blocker(stats, skill) != "":
		return false
	skill_levels[String(skill.id)] = skill_level(skill) + 1
	save_file()
	changed.emit()
	return true


## Gives back every SP (default skills stay at Lv 1); skills that are no longer
## learned leave the quickslots.
func reset_skills(stats: PlayerStats) -> void:
	skill_levels = {}
	for i in quickslots.size():
		var entry: String = quickslots[i]
		if entry.begins_with("skill:"):
			var s := find_skill(stats, StringName(entry.trim_prefix("skill:")))
			if s == null or skill_level(s) <= 0:
				quickslots[i] = ""
	save_file()
	changed.emit()


func quickslot(index: int) -> String:
	return String(quickslots[index]) if index >= 0 and index < quickslots.size() else ""


func set_quickslot(index: int, entry: String) -> void:
	if index < 0 or index >= quickslots.size():
		return
	# One entry lives in one slot: placing it again moves it.
	if entry != "":
		for i in quickslots.size():
			if quickslots[i] == entry:
				quickslots[i] = ""
	quickslots[index] = entry
	save_file()
	changed.emit()


func swap_quickslots(a: int, b: int) -> void:
	var t: String = quickslots[a]
	quickslots[a] = quickslots[b]
	quickslots[b] = t
	save_file()
	changed.emit()


## Share of incoming damage that `defense` blocks (same formula as Player.take_hit).
static func damage_reduction(defense: float) -> float:
	return defense / (100.0 + defense)


func reset() -> void:
	level = 1
	experience = 0
	gold = 0
	difficulty = 0
	unlocked = 0
	skill_levels = {}
	quickslots = DEFAULT_QUICKSLOTS.duplicate()
	Inventory.clear()
	save_file()
	changed.emit()


# --- Difficulty -----------------------------------------------------------------

func dungeon_level() -> int:
	return int(DIFFICULTIES[difficulty][1])


func difficulty_name(index := -1) -> String:
	return String(DIFFICULTIES[difficulty if index < 0 else index][0])


## A difficulty is open once the one before it was cleared, or once the
## character has reached its dungeon level.
func is_unlocked(index: int) -> bool:
	return index <= unlocked or level >= int(DIFFICULTIES[index][1])


func set_difficulty(index: int) -> void:
	if index < 0 or index >= DIFFICULTIES.size() or not is_unlocked(index):
		return
	difficulty = index
	save_file()
	changed.emit()


## Called when the boss falls: opens the next difficulty.
func on_dungeon_cleared() -> void:
	if difficulty >= unlocked and unlocked < DIFFICULTIES.size() - 1:
		unlocked = difficulty + 1
	save_file()
	changed.emit()


## Copy of an enemy's stats, grown to the current dungeon level. Also scales its
## EXP, cut to a quarter when the character far outlevels the dungeon.
func scale_enemy(base: EnemyStats) -> EnemyStats:
	var s: EnemyStats = base.duplicate()
	var up := float(dungeon_level() - 1)
	s.max_hp = base.max_hp * (1.0 + ENEMY_HP_GROWTH * up)
	s.attack_power = base.attack_power * (1.0 + ENEMY_ATK_GROWTH * up)
	s.defense = base.defense + ENEMY_DEF_GROWTH * up
	var exp_amount := float(base.exp_reward) * (1.0 + ENEMY_EXP_GROWTH * up)
	if level > dungeon_level() + EXP_LEVEL_GAP:
		exp_amount *= 0.25
	s.exp_reward = maxi(1, roundi(exp_amount))
	s.gold_min = roundi(base.gold_min * (1.0 + 0.2 * up))
	s.gold_max = roundi(base.gold_max * (1.0 + 0.2 * up))
	s.display_name = "%s  Lv %d" % [base.display_name, dungeon_level()]
	return s


func add_gold(amount: int) -> void:
	gold += maxi(amount, 0)
	save_file()
	changed.emit()


func save_file() -> void:
	if not _saving:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("character", "level", level)
	cfg.set_value("character", "experience", experience)
	cfg.set_value("character", "gold", gold)
	cfg.set_value("character", "difficulty", difficulty)
	cfg.set_value("character", "unlocked", unlocked)
	cfg.set_value("skills", "levels", skill_levels)
	cfg.set_value("skills", "quickslots", quickslots)
	cfg.set_value("inventory", "data", Inventory.serialize())
	cfg.save(_path)


func load_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_path) != OK:
		return
	level = clampi(int(cfg.get_value("character", "level", 1)), 1, MAX_LEVEL)
	experience = maxi(int(cfg.get_value("character", "experience", 0)), 0)
	gold = maxi(int(cfg.get_value("character", "gold", 0)), 0)
	unlocked = clampi(int(cfg.get_value("character", "unlocked", 0)), 0, DIFFICULTIES.size() - 1)
	difficulty = clampi(int(cfg.get_value("character", "difficulty", 0)), 0, unlocked)
	var levels: Variant = cfg.get_value("skills", "levels", {})
	skill_levels = levels if levels is Dictionary else {}
	var slots: Variant = cfg.get_value("skills", "quickslots", [])
	if slots is Array and (slots as Array).size() == DEFAULT_QUICKSLOTS.size():
		quickslots = slots
	var bag: Variant = cfg.get_value("inventory", "data", {})
	if bag is Dictionary:
		Inventory.deserialize(bag)


## Tests save to a scratch file (and turn saving on) to check saving and loading.
func use_file(path: String) -> void:
	_path = path
	_saving = true
