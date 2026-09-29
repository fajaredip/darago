class_name EnemyStats
extends Resource
## Angka-angka satu jenis musuh. Ubah di Inspector.

@export var display_name := "Tengkorak"
## Tampilkan nama di atas bar HP.
@export var show_name := false
@export var max_hp := 90.0
@export var attack_power := 28.0
## Mengurangi damage yang diterima.
@export var defense := 0.0
@export var move_speed := 4.2

@export_group("Serangan")
## Jarak mulai ancang-ancang menyerang.
@export var attack_range := 1.9
## Jangkauan pukulan.
@export var attack_radius := 2.3
## Lebar sudut pukulan (360 = sekeliling).
@export_range(10.0, 360.0) var attack_arc := 100.0
## Lama ancang-ancang (tanda merah). Makin lama, makin mudah dihindari.
@export var windup := 0.65
## Bagian awal ancang-ancang di mana musuh masih memutar badan mengikuti pemain (0-1).
@export_range(0.0, 1.0) var track_fraction := 0.5
@export var attack_cooldown := 1.8
## Jeda diam setelah menyerang (kesempatan pemain membalas).
@export var recover_time := 0.6
@export var attack_knockback := 5.0
## Serangan hanya kena target yang menapak tanah (bisa dihindari dengan lompat).
@export var ground_only := false

@export_group("Ketahanan")
## 0 = terpental penuh, 1 = tidak terpental.
@export_range(0.0, 1.0) var knockback_resist := 0.0
## 0 = bisa dilempar ke udara, 1 = tidak bisa.
@export_range(0.0, 1.0) var launch_resist := 0.0
## Tidak terhenti saat dipukul ketika sedang ancang-ancang.
@export var armored_windup := false

@export_group("Tampilan")
## Ukuran badan untuk tabrakan dan area kena.
@export var size := 1.0
@export var color := Color(0.45, 0.72, 0.35)
## Suara dan guncangan lebih berat.
@export var heavy := false

@export_group("Model")
@export var model: PackedScene
@export var model_scale := 1.0
@export var weapon: PackedScene
@export var weapon_bone: StringName = &"handslot.r"
@export var weapon_position := Vector3.ZERO
## Rotasi senjata (derajat).
@export var weapon_rotation := Vector3.ZERO
## Titik pangkal dan ujung senjata (di ruang model senjata) untuk jejak ayunan.
@export var weapon_trail_base := Vector3(0, 0.25, 0)
@export var weapon_trail_tip := Vector3(0, 1.1, 0)

@export_group("Animasi")
@export var anim_idle: StringName = &"Idle"
@export var anim_move: StringName = &"Running_A"
## Kecepatan gerak (m/s) saat animasi jalan diputar normal.
@export var move_anim_reference_speed := 4.0
@export var anim_attack: StringName = &"1H_Melee_Attack_Chop"
## Detik di animasi serangan saat senjata kena; diselaraskan dengan akhir ancang-ancang.
@export var attack_anim_contact := 0.45
@export var anim_hit: StringName = &"Hit_A"
@export var anim_air: StringName = &"Hit_B"
@export var anim_down: StringName = &"Death_A"
@export var anim_getup: StringName = &"Lie_StandUp"
@export var anim_getup_offset := 1.0
@export var anim_death: StringName = &"Death_C_Skeletons"
@export var anim_spawn: StringName = &"Spawn_Ground_Skeletons"
@export var anim_spawn_speed := 3.0
