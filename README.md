# Darago

Prototype action RPG 3D bergaya anime, terinspirasi rasa Dragon Nest klasik:
combat cepat berbasis combo, dodge, lompat + serangan udara, skill, dan musuh
dengan tanda serangan yang bisa dihindari. Dibuat dengan Godot 4.7.2 (GDScript).

![Warrior berlari di dungeon](docs/run.png)
![Combo dengan jejak pedang](docs/combat.png)

Semua aset pihak ketiga berlisensi bebas (CC0 / CC BY / OFL / MIT); ikon item dan UI
perkamen dibuat dengan ChatGPT khusus untuk proyek ini. Daftar lengkapnya di
[game/CREDITS.md](game/CREDITS.md). Tidak ada aset, nama, atau desain dari
Dragon Nest.

## Menjalankan

1. Unduh **Godot 4.7.2 Standard** (bukan .NET) untuk Windows dari
   https://godotengine.org/download/archive/4.7.2-stable/
2. Ekstrak `Godot_v4.7.2-stable_win64.exe` (dan `_console.exe`) ke folder
   `tools/godot/`.
3. Klik dua kali **`Main Game.bat`** untuk main, atau **`Buka Editor.bat`**
   untuk membuka editor. Pembukaan pertama butuh waktu untuk mengimpor aset.

Tanpa file .bat: buka `game/project.godot` dengan Godot 4.7.2.

## Kontrol

| Tombol | Aksi |
|---|---|
| WASD + mouse | gerak dan kamera (karakter menghadap arah kamera) |
| Klik kiri (tahan) | combo 3 tebasan |
| Klik kanan | tebasan naik (melempar musuh ke udara) |
| Spasi | lompat; di udara klik kiri = combo udara, klik kanan = hantaman terjun |
| Tekan arah 2x cepat (atau Shift) | dodge |
| 1 / 2 (atau Q / E) | skill Tebasan Terjang / Putaran Badai |
| Tahan Alt | kursor mouse |
| F1 | tampilkan / sembunyikan daftar tombol (otomatis mengecil setelah 20 detik) |
| C | jendela status (level, EXP, STR/AGI/INT/VIT, stat tempur) |
| I | inventory: pakai / lepas equipment, enhance (+1 sampai +5), jual item (game di-pause) |
| `\` | screenshot (tersalin ke clipboard + disimpan di `screenshots/`) |
| Esc | menu pengaturan (game di-pause): ganti tombol, sensitivitas mouse, volume, keluar |

Semua tombol di atas (kecuali Esc) bisa diganti lewat **Esc > Control Setting**.
Pengaturan tersimpan otomatis di `%APPDATA%\Godot\app_userdata\Darago\settings.cfg`.

## Struktur

- `game/scripts/` kode (player, musuh, kamera, HUD, efek, arena)
- `game/data/` angka yang bisa diubah di Inspector: class (`classes/warrior.tres`),
  serangan (`attacks/`), musuh (`enemies/`)
- `game/assets/` model, animasi, dan potongan dungeon
- `game/tests/` test otomatis dan alat bantu

## Test

```
tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --fixed-fps 60 -- --smoke-test
tools/godot/Godot_v4.7.2-stable_win64_console.exe --path game -- --fps-probe
```

## Catatan teknis

`game/addons/vrm` (godot-vrm v2.6.1) ditambal supaya model VRM 0.x menghadap +Z
saat retarget; tanpa itu gerakan lengan animasi terbalik. Lihat penanda
`DARAGO PATCH` dan [game/CREDITS.md](game/CREDITS.md).
