# Laporan uji v0.1

Mesin: MacBook Pro 14" M1 Pro, macOS 27.2, Swift 6.4 (Command Line Tools, tanpa Xcode). 4 Nov 2026.

## Otomatis

`./scripts/build.sh --test` → **144 unit test lulus** (36 suite) + bundel `build/Dylan.app` ter-sign (ad-hoc, hardened runtime).

| Area | Yang diuji |
|---|---|
| Notch & aktivitas | Prioritas P0–P3, Duo, hold 5/8 s, jeda saat hover, fullscreen hanya P0, riwayat 20, post mempertahankan state, geometri dari safe area, pill |
| Bridge & CLI | Round-trip semua pesan, progress di-clamp, batas 64 KB, socket 0600 + peer uid, MCP JSON-RPC (initialize, tools/list, tools/call, error) |
| Agents | Parser hook, siklus sesi, pemangkasan payload, sesi basi kedaluwarsa, hook ber-path quote, uninstall menjaga grup user, notify Codex di config.toml |
| Command | Daftar abaikan, threshold, urutan start/end dengan nomor urut (tanpa perintah hantu), label perintah |
| Clipboard | JWT/JSON/timestamp/Base64/URL/UUID/warna/path, pola rahasia di mana saja (baris `.env`, `Authorization: Bearer`, `postgres://user:pass@`) + masking, rahasia tidak pernah persist, pin & batas |
| Stats & port | CPU dari ticks, rate jaringan, parser `ps`, alert 150% × 60 s sekali per streak, parser `lsof` + filter port sistem |
| Media | Parser LRC (tag ganda, offset), respons LRCLIB, link Spotify → URI (menolak injeksi AppleScript) |
| Home | Tambah cepat ("Rapat tim besok 10.00", "jam 3", "jumat"), forecast & geocode Open-Meteo, koordinat dibulatkan |
| Shelf & file | Shelf (dedupe, batas, file hilang, nama zip, hasil tidak pernah menimpa file), deteksi goyang untuk floating basket, download Chrome/Firefox/Safari |
| Dev | `docker ps`, `gh run list`, remote → repo (termasuk `alice.github.io`), kegagalan CI baru, interval polling, widget (interval, JSON), `Shell.run` dengan output 200 KB dan timeout |
| Discord | Reducer READY → AUTHORIZE → AUTHENTICATE → voice, urutan pembicara, keluar channel, DM, perintah RPC, handshake lewat unix socket dengan server Discord palsu |
| Face Unlock | 11 aturan penolakan (waktu kunci tidak diketahui = tolak), jaringan tepercaya, tantangan liveness (foto statis timeout, gerakan salah, ganti wajah, dua wajah, orang lain), audit log |
| Lainnya | Keep awake, format warna, Touch ID sudo, profil, bahasa (key & argumen id/en sama, semua `L("…")` ada), katalog fitur mencakup semua FR di PRD |

## Live di Mac ini

| Fitur | Hasil |
|---|---|
| Panel notch | Island menempel di tepi atas (setelah fix `constrainFrameRect`), klik tembus, idle CPU 0,0–0,3%, RSS 60–100 MB. Agent + perintah berjalan: 2–4% (sebelumnya 8–10% karena spinner `TimelineView`) |
| CLI | activity/notify/run (exit code diteruskan)/doctor/debug state/shelf add/mcp |
| Claude Code | Sesi Claude Code ini sendiri terlacak lewat hook yang kamu pasang |
| zsh | Shell interaktif asli: `cd` tidak muncul, `sleep 3; false` → ✗ exit 1, hilang setelah 8 s |
| Spotify | Now Playing dengan artwork asli (Avenged Sevenfold) |
| Clipboard | Token `ghp_…`, `export GITHUB_TOKEN=ghp_…` dan `DATABASE_URL=postgres://app:…@…` disamarkan dan tidak pernah tertulis ke `clipboard.json` (0600); teks biasa tetap tersimpan |
| Stats | CPU dengan sparkline, GPU, memori, jaringan, disk, baterai, proses teratas |
| Port | node/mysqld/postgres/Python terdeteksi dengan nama project; `localhost:5173 siap` |
| Shelf | `dylan shelf add`, ikon, aksi |
| Cuaca | Jakarta dari Open-Meteo (diaktifkan sementara, pengaturan dikembalikan) |
| MCP & Codex | `tools/list` → 3 tool; notify tampil; event Codex → "Codex finished" |
| HUD | Volume +2% → bar di telinga (volume dikembalikan) |
| Vision | OCR dan hapus background (foto `Whiterose.heic`) dengan API yang sama |
| Format data asli | LRCLIB, Open-Meteo, `gh run list`, `lsof` cocok dengan parser |

## Bug yang ditemukan dan diperbaiki
- 3 crash isolasi Swift 6 (socket accept, simpan clipboard di background, dan pola yang sama dicegah di provider lain).
- Island di bawah menu bar; durasi agent tidak reset; snapshot menulis preferensi; perintah hantu dari urutan start/end; hasil perintah terhapus oleh perintah berikutnya; label port memakai pemisah ribuan; modifier SwiftUI tertelan komentar.
- 24 temuan review independen pertama (deteksi hook ber-quote, AppleScript bisa membuka Spotify, kebocoran Mode Presentasi, edit config yang tidak aman, fokus keyboard dicuri, dan lainnya).
- 22 temuan review independen kedua, antara lain: crash saat Reminders dimuat (callback EventKit di background), rahasia di baris `.env`/header/URL tersimpan polos, kamera cermin menyala setelah panel tertutup, konversi PNG→PNG menimpa file asli, download parsial basi tampil selamanya, aktivitas CI/widget tertinggal, "Buka di editor" bisa menjalankan `.command`, drag lama membuka Shelf, kebocoran Mode Presentasi di tab Dev/Agents, `Shell.run` macet pada output > 64 KB, prompt izin Desktop dari Shelf.

## Belum diverifikasi (butuh izin, perangkat, atau akun kamu)
- Prompt izin yang sengaja tidak dipicu: Kalender, Reminders, Bluetooth, kamera (cermin), folder Downloads, Accessibility.
- Discord asli (butuh Client ID), jawab izin dari notch pada sesi Claude asli (opt-in), video compress, floating basket, screenshot otomatis ke shelf.
- Mode Presentasi saat share layar di Zoom/Meet, monitor eksternal, 120 fps.
- Fitur yang belum dibuat: lihat Settings → Fitur yang didukung.
