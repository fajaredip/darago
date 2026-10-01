class_name SkillData
extends Resource
## Satu skill di skill tree sebuah class (seperti Dragon Nest): aktif (dipakai
## lewat quickslot) atau pasif (bonus stat). Level dinaikkan dengan SP.

enum Kind { ACTIVE, PASSIVE }

@export var id: StringName = &""
@export var display_name := "Skill"
@export_multiline var description := ""
@export var icon: Texture2D
@export var kind := Kind.ACTIVE
## Sel di jendela skill: kolom (0-3), baris (0..).
@export var grid_pos := Vector2i.ZERO

@export_group("Belajar")
## Skill bawaan: sudah Lv 1 sejak awal, tanpa SP.
@export var default_skill := false
@export_range(1, 10) var max_level := 5
## SP untuk Lv 1, lalu untuk tiap level berikutnya.
@export var sp_first := 3
@export var sp_per_level := 2
## Level karakter untuk Lv 1; tiap level skill berikutnya butuh `level_step` lagi.
@export var required_level := 1
@export var level_step := 2
## Skill lain yang harus sudah mencapai `requires_level` dulu (kosong = tidak ada).
@export var requires: StringName = &""
@export var requires_level := 1

@export_group("Aktif")
@export var attack: AttackData
## Per level di atas 1: tambahan damage, pengurangan cooldown, tambahan MP (pecahan).
@export var damage_per_level := 0.1
@export var cooldown_per_level := 0.04
@export var mana_per_level := 0.08
## Buff ATK saat dipakai (0 = tidak ada), lamanya dalam detik.
@export var buff_attack := 0.0
@export var buff_attack_per_level := 0.0
@export var buff_duration := 0.0

@export_group("Pasif")
## "HP%", "DEF%", "CRIT" (tambahan peluang) atau "MP_REGEN%".
@export_enum("HP%", "DEF%", "CRIT", "MP_REGEN%") var passive_stat := "HP%"
@export var passive_per_level := 0.04


func sp_cost(to_level: int) -> int:
	return sp_first if to_level <= 1 else sp_per_level


## Character level needed to reach `to_level` of this skill.
func level_needed(to_level: int) -> int:
	return required_level + level_step * maxi(to_level - 1, 0)


## The attack as used at `level`: stronger, faster cooldown, more MP.
func attack_at(level: int) -> AttackData:
	var a: AttackData = attack.duplicate()
	var up := float(maxi(level, 1) - 1)
	a.damage_multiplier = attack.damage_multiplier * (1.0 + damage_per_level * up)
	a.cooldown = attack.cooldown * maxf(0.3, 1.0 - cooldown_per_level * up)
	a.mana_cost = attack.mana_cost * (1.0 + mana_per_level * up)
	if icon:
		a.icon = icon
	a.display_name = display_name
	return a


func buff_at(level: int) -> float:
	return buff_attack + buff_attack_per_level * float(maxi(level, 1) - 1)


func passive_at(level: int) -> float:
	return passive_per_level * float(level)


## Short effect text for the tooltip at `level` (0 = not learned).
func effect_text(level: int) -> String:
	if level <= 0:
		return "Belum dipelajari"
	if kind == Kind.PASSIVE:
		var v := passive_at(level)
		match passive_stat:
			"CRIT":
				return "Critical +%.1f%%" % (v * 100.0)
			"HP%":
				return "HP +%d%%" % roundi(v * 100.0)
			"DEF%":
				return "DEF +%d%%" % roundi(v * 100.0)
			_:
				return "Regen MP +%d%%" % roundi(v * 100.0)
	var a := attack_at(level)
	var text := "Damage %d%%   MP %d   Cooldown %.1f dtk" % [roundi(a.damage_multiplier * 100.0 * a.hits), roundi(a.mana_cost), a.cooldown]
	if buff_duration > 0.0:
		text += "\nATK +%d%% selama %d dtk" % [roundi(buff_at(level) * 100.0), roundi(buff_duration)]
	return text
