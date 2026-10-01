class_name PlayerStats
extends Resource
## Satu class karakter (mis. Warrior): status, gerak, jurus, model dan animasi.
## Ubah di Inspector untuk menyetel rasa game. Class baru = file .tres baru.

@export var class_display_name := "Warrior"

@export_group("Stat Utama")
## Nilai di Lv 1. HP, MP, ATK, DEF dan crit di grup "Status" dihitung dari
## stat ini (plus level) saat game jalan; lihat scripts/core/progress.gd.
@export var base_str := 20.0
@export var base_agi := 10.0
@export var base_int := 8.0
@export var base_vit := 16.0
## Tambahan tiap naik level.
@export var growth_str := 3.0
@export var growth_agi := 1.0
@export var growth_int := 1.0
@export var growth_vit := 2.5

@export_group("Status")
@export var max_hp := 500.0
@export var max_mana := 100.0
## Mana yang pulih per detik.
@export var mana_regen := 5.0
@export var attack_power := 22.0
## Mengurangi damage yang diterima.
@export var defense := 5.0
@export_range(0.0, 1.0) var crit_chance := 0.15
@export var crit_multiplier := 1.8

@export_group("Gerak")
@export var move_speed := 7.0
@export var acceleration := 70.0
## Kecepatan badan berputar mengikuti arah kamera.
@export var turn_speed := 20.0
@export var gravity := 30.0
## Kecepatan awal lompat (makin besar, makin tinggi).
@export var jump_velocity := 10.0
## Kontrol arah saat di udara (0 = tidak bisa belok, 1 = sama seperti di tanah).
@export_range(0.0, 1.0) var air_control := 0.35

@export_group("Dodge")
@export var dodge_distance := 5.0
@export var dodge_duration := 0.32
## Lama kebal damage saat dodge.
@export var dodge_iframes := 0.28
@export var dodge_cooldown := 0.5
## Dihitung dari awal serangan: kapan dodge boleh membatalkan serangan.
@export var dodge_cancel_after := 0.1
## Jeda maksimum antara dua tekanan arah yang sama supaya jadi dodge (detik).
@export var double_tap_window := 0.25

@export_group("Skill")
## Folder with this class's skill tree (one SkillData .tres per skill).
@export_dir var skill_dir := "res://data/skills/warrior"

@export_group("Combat")
## Urutan combo klik kiri.
@export var combo: Array[AttackData] = []
## Serangan berat klik kanan.
@export var heavy: AttackData
## Urutan combo klik kiri saat di udara.
@export var air_combo: Array[AttackData] = []
## Klik kanan saat di udara.
@export var air_heavy: AttackData
## Skill tombol 1.
@export var skill_1: AttackData
## Skill tombol 2.
@export var skill_2: AttackData
## Lama tombol "diingat" kalau ditekan saat karakter masih sibuk.
@export var input_buffer := 0.3
## Lama terhuyung saat kena pukul.
@export var hurt_stun := 0.35
## Kebal sebentar setelah kena pukul (supaya tidak dipukuli beruntun).
@export var hurt_iframes := 0.6

@export_group("Model")
## Model karakter (.vrm dari VRoid atau model humanoid lain).
@export var model: PackedScene
## Library animasi humanoid yang dipakai model ini.
@export var animation_libraries: Dictionary = {}
@export var model_scale := 1.0
## Model senjata di tangan kanan.
@export var weapon: PackedScene
@export var weapon_bone: StringName = &"RightHand"
@export var weapon_position := Vector3.ZERO
## Rotasi senjata (derajat).
@export var weapon_rotation := Vector3.ZERO
@export var weapon_scale := 1.0
## Titik pangkal dan ujung bilah (di ruang model senjata) untuk jejak tebasan.
@export var weapon_trail_base := Vector3(0, 0.4, 0)
@export var weapon_trail_tip := Vector3(0, 1.9, 0)

@export_group("Animasi")
@export var anim_idle: StringName = &""
@export var anim_run: StringName = &""
## Kecepatan lari (m/s) saat animasi lari diputar normal; dipakai menyamakan langkah kaki.
@export var run_anim_reference_speed := 7.0
@export var anim_jump: StringName = &""
@export var anim_jump_offset := 0.0
@export var anim_air: StringName = &""
@export var anim_land: StringName = &""
@export var anim_land_offset := 0.0
@export var anim_dodge: StringName = &""
## Bagian animasi dodge yang dipakai (detik); diputar selama dodge_duration.
@export var anim_dodge_length := 0.9
@export var anim_hurt: StringName = &""
@export var anim_death: StringName = &""
## Saat lari / lompat, tulang-tulang ini (lengan pemegang senjata) dikunci di pose
## animasi berikut, supaya senjata tetap stabil sementara badan berlari.
@export var hold_pose_bones: PackedStringArray = []
@export var hold_pose_anim: StringName = &""
@export var hold_pose_time := 0.0
