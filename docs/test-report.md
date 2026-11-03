# Laporan uji v0.1 (Phase 0 + v1.0 inti)

Mesin: MacBook Pro 14" M1 Pro, macOS 27.2, Swift 6.4 (Command Line Tools, tanpa Xcode). 4 Nov 2026.

## Otomatis

`./scripts/build.sh --test` → **61 unit test lulus** (14 suite) + bundel `build/Dylan.app` ter-sign (ad-hoc, hardened runtime).

| Area | Yang diuji |
|---|---|
| ActivityCenter (§2.4) | Prioritas + terbaru, Duo/1 slot, fullscreen hanya P0, hasil 5 s / 8 s, jeda saat hover, P0 tidak kedaluwarsa, riwayat 20 tanpa ambient |
| Geometri | Notch dari safe area, ukuran tiap state, panel menempel tepi atas, pill tanpa notch |
| Bridge | Round-trip semua pesan, contoh PRD, versi/tipe/hasil salah ditolak, batas 64 KB, socket 0600 + peer uid, connect gagal cepat |
| Hook Claude | Semua fixture ter-parse, siklus sesi lengkap, izin dari notch, payload besar dipangkas, output izin allow/deny/passthrough |
| settings.json | File kosong, hook user lain utuh, idempoten, app dipindah → update path, JSON rusak ditolak, lepas hook = kembali ke isi semula |
| Command | Daftar abaikan (vim, ssh, `tail -f`, server), threshold, hasil hanya saat terminal di belakang |
| Meeting, timer, baterai, profil, bahasa | Link Zoom/Meet/Teams + `zoommtg://`, fase 10 m / 1 m, timer tahan sleep, siklus Pomodoro, parser "45m/1h30", ambang 20%/10%, fitur [Dev] terkunci di profil Umum |
| Lokalisasi (FR-18) | id dan en punya key & argumen format yang sama; semua `L("…")` di kode ada terjemahannya |

## Live (app asli, lewat CLI + `dylan debug state`)

| Skenario | Hasil |
|---|---|
| `dylan activity start/update/end` | Compact dengan progress → ✓ hasil → hilang setelah 5 s |
| `dylan run -- sh -c 'sleep 2; exit 3'` | Exit code 3 diteruskan |
| Shell `npm test` (threshold 2 s) lalu exit 1 | Muncul setelah threshold → ✗ `exit 1` |
| Shell `vim x` | Tidak tampil |
| Hook SessionStart → UserPromptSubmit → PreToolUse → PermissionRequest → Stop → SessionEnd | Bekerja → P0 izin + Peek otomatis → ✓ Selesai → kembali Closed |
| `dylan hook claude` (event biasa) | < 50 ms; tanpa output |
| `PermissionRequest`, "Jawab dari notch" mati (default) | Dilepas ke terminal dalam 20 ms |
| App tidak berjalan | Hook & `notify` exit 0, hook tanpa output |
| Idle 30 s | CPU 0,0%, RSS 69 MB |
| Snapshot D2–D32 (id & en) | Dirender; dicek terhadap design |

## Bug yang ditemukan saat uji (sudah diperbaiki)
1. App crash pada koneksi socket pertama: closure main-actor dipanggil dari queue background (cek isolasi Swift 6).
2. Island muncul di bawah menu bar (AppKit membatasi frame jendela).
3. Durasi agent tidak reset saat prompt baru (`upsert` menyimpan `startedAt` lama).
4. `--snapshot` menulis profil Developer ke preferensi user.
5. Notifikasi `permission_prompt` menampilkan teks pesan sebagai nilai di telinga.

## Belum diuji (butuh kamu / perangkat)
- Klik Izinkan/Tolak dari notch pada sesi Claude Code asli (butuh hook terpasang, PRD T0.4).
- Spotify/Music live (Spotify tidak berjalan saat uji; prompt Automation).
- Meeting dari Kalender asli (izin Kalender), AirPods tersambung, colok/cabut charger.
- Mode Presentasi saat share layar di Zoom/Meet (`sharingType`).
- 120 fps animasi, monitor eksternal/pill.
- Checklist manual Bagian 5 PRD selebihnya.
