class_name AttackData
extends Resource
## Satu serangan atau skill. Waktu dalam detik, jarak dalam meter.
## Ubah angka di Inspector untuk menyetel rasa serangan.

@export var display_name := "Serangan"
## Ikon di bar skill (kosong = ikon bawaan slot).
@export var icon: Texture2D

@export_group("Waktu")
## Ancang-ancang sebelum pukulan kena.
@export var startup := 0.1
## Lama area serangan aktif (bisa kena musuh).
@export var active := 0.06
## Jeda setelah fase aktif sebelum kembali bebas.
@export var recovery := 0.25
## Dihitung dari awal serangan: kapan serangan / skill berikutnya boleh menyambung.
@export var cancel_after := 0.2
## Titik di fase aktif (0-1) saat damage mulai masuk. Samakan dengan saat pedang
## lewat di depan karakter, supaya hitstop membekukan pedang tepat di musuh.
@export_range(0.0, 1.0) var hit_point := 0.0

@export_group("Area kena")
## Jangkauan serangan.
@export var radius := 2.8
## Lebar sudut serangan di depan karakter (360 = sekeliling).
@export_range(10.0, 360.0) var arc_degrees := 120.0
## Beda tinggi maksimum dengan musuh (untuk musuh yang melayang).
@export var height := 1.8
## Berapa kali musuh yang sama bisa kena dalam satu serangan.
@export var hits := 1
## Jeda antar kena untuk serangan multi-hit.
@export var hit_interval := 0.12

@export_group("Dampak")
## Pengali damage dari attack_power karakter.
@export var damage_multiplier := 1.0
## Lama game "membeku" saat pukulan kena. Kunci rasa pukulan mantap.
@export var hitstop := 0.06
## Lama musuh terhuyung setelah kena.
@export var hitstun := 0.35
## Kekuatan dorongan ke samping (m/s).
@export var knockback := 2.5
## Dorongan ke atas (m/s). Di atas 0 = musuh terlempar ke udara.
@export var launch := 0.0
## Musuh jatuh terbaring setelah kena.
@export var knockdown := false
## Dorong musuh searah hadap karakter (bukan menjauh dari karakter).
@export var push_along_facing := false
## Mana yang didapat tiap kena.
@export var mana_gain := 3.0
## Guncangan kamera saat kena (0-1).
@export_range(0.0, 1.0) var camera_shake := 0.05

@export_group("Gerakan")
## Maju sejauh ini selama ancang-ancang + fase aktif.
@export var lunge_distance := 0.7
## Menembus musuh selama serangan (untuk skill terjang).
@export var pass_through := false
## Kebal damage selama sekian detik dari awal serangan.
@export var iframes := 0.0
## Tidak terhuyung saat dipukul selama serangan ini (damage tetap masuk).
@export var super_armor := false

@export_group("Udara")
## Serangan udara: karakter melayang dengan kecepatan naik ini (m/s) saat mulai menyerang.
@export var air_float := 0.0
## Serangan terjun: meluncur ke bawah, lalu menghantam saat mendarat.
@export var plunge := false
## Kecepatan meluncur ke bawah untuk serangan terjun (m/s).
@export var plunge_speed := 24.0
## Gelombang kejut di lantai saat damage mulai masuk.
@export var impact_ring := false
## Jarak gelombang kejut di depan karakter (0 = di kaki).
@export var impact_offset := 0.0
## Besar gelombang kejut (0 = sama dengan jangkauan serangan).
@export var impact_radius := 0.0

@export_group("Skill")
@export var mana_cost := 0.0
@export var cooldown := 0.0

@export_group("Animasi")
## Nama animasi, mis. "ual2/Sword_Regular_A".
@export var animation: StringName = &""
@export var anim_speed := 1.0
## Mulai animasi dari detik ke- (lewati bagian awal yang lambat).
@export var anim_offset := 0.0
## Bekukan pose di detik ini selama serangan (untuk skill putar). -1 = tidak.
@export var anim_hold := -1.0
## Animasi saat jeda akhir kalau combo tidak disambung.
@export var recovery_animation: StringName = &""
@export var recovery_anim_speed := 1.0
## Serangan terjun: mainkan animasi dari detik ini saat mendarat.
@export var land_anim_offset := -1.0

@export_group("Tampilan")
## Warna jejak tebasan, percikan dan gelombang kejut serangan ini.
@export var color := Color(1.0, 0.97, 0.9)
## Putaran badan penuh selama fase aktif (untuk skill putar).
@export var model_spins := 0
@export var swing_sound := "swing"
@export var hit_sound := "hit"
## Karakter berteriak saat mengayun (untuk serangan besar dan skill).
@export var voice := false
