# Dylan

**Dynamic Island untuk Mac. Untuk semua orang, dengan banyak fitur khusus engineer.**

Dylan mengubah notch MacBook menjadi pusat status yang hidup: musik, Discord, notifikasi, baterai, dan meeting muncul kecil di samping notch, lalu menyingkir sendiri setelah selesai. Fitur terbaik dari Droppy, Atoll, DynamicLake, dan Alcove digabung dalam satu app gratis.

Buat software engineer, Dylan punya **Mode Developer**: pantau agent AI, perintah panjang, CI, dan dev server langsung dari notch. Pengguna biasa tidak akan melihat fitur ini sama sekali; engineer cukup menyalakannya sekali.

> **Status:** v0.1, dalam pengembangan. Phase 0 (spike) dan sebagian besar v1.0 sudah ada; lihat [docs/test-report.md](docs/test-report.md). Spesifikasi lengkap ada di [PRD.md](PRD.md).

## Fitur untuk semua orang

- **Musik:** kontrol penuh Spotify & Apple Music (shuffle, repeat, volume, love), putar playlist favorit sekali klik, lirik tersinkron, pilih output audio, volume per app, equalizer yang mengikuti musik, akun Spotify opsional (simpan lagu, playlist, lagu berikutnya). Media dari browser (YouTube dll.) menyusul.
- **Discord:** siapa yang sedang bicara di voice, mute/deafen/keluar, DM & mention, langsung dari notch.
- **Notifikasi & pesan:** notifikasi app di notch, balas lewat banner, panggilan masuk Terima/Tolak, kontrol mic/kamera/share untuk Zoom, Teams, dan Meet.
- **Perangkat:** HUD volume/brightness, animasi charging, baterai AirPods, indikator kamera/mikrofon, Focus.
- **Produktivitas:** countdown meeting + tombol Join, "waktunya berangkat" ke meeting di lokasi fisik, reminder, timer/Pomodoro, shelf file + AirDrop, clipboard, color picker, keep awake, cuaca, progres download, widget lock screen (eksperimental).
- **Mode Presentasi:** sembunyikan isi sensitif saat screen share, bisa menyala otomatis saat kamu share layar (eksperimental).
- **Bahasa Indonesia & English:** pilih di Settings, atau ikuti bahasa sistem.

## Fitur untuk engineer (Mode Developer)

- **Agent AI:** status Claude Code (tool & file yang sedang dikerjakan), notifikasi saat agent butuh izin atau selesai, lengkap dengan durasi dan `+x −y` baris. Izin bisa dijawab langsung dari notch. Codex CLI, Cursor, dan OpenCode juga tampil.
- **Command tracker:** `npm test`, build, migrasi, deploy. Notch memberi tahu saat selesai/gagal, lengkap dengan durasi dan exit code.
- **Live Activity API:** script apa pun bisa menampilkan progres di notch lewat CLI `dylan` (contoh di bawah).
- **Dev server & port:** port mana dipakai project apa, buka di browser, atau matikan.
- **GitHub:** status GitHub Actions di branch yang sedang dikerjakan dan jumlah PR yang menunggu review-mu.
- **Clipboard developer:** decode JWT, pretty-print JSON, Unix timestamp ↔ tanggal, Base64, UUID, hash. Token dan password otomatis disamarkan dan tidak pernah disimpan ke disk.
- **Stats + alert:** CPU, memori, jaringan; peringatan saat proses seperti `node` atau `docker` nyangkut memakan CPU.
- **Script widget, Docker, terminal cepat di notch (⌃⌥T), MCP server** untuk Claude Code.
- **Touch ID untuk `sudo`.**
- **Face Unlock (eksperimental):** buka kunci dengan wajah, dengan tantangan acak dan batas ala Apple. Bukan Face ID; lihat `docs/face-unlock.md`.

## Live Activity API

```bash
dylan activity start deploy --title "Deploy staging" --progress 0
dylan activity update deploy --progress 0.6 --subtitle "migrasi DB"
dylan activity end deploy --success --detail "v2.4.1 · 3m 10s"
```

## Build & jalankan

Cukup Command Line Tools (tanpa Xcode), macOS 15+, Apple Silicon.

```bash
./scripts/build.sh --test --run   # unit test, bundel build/Dylan.app, lalu jalankan
```

- CLI ada di `Dylan.app/Contents/Helpers/dylan`. Settings → Terminal → "Pasang CLI" membuat symlink `~/.local/bin/dylan`.
- Mode Developer: Settings → Umum → Profil → Developer, lalu Settings → Agents → Pasang hook (diff ditampilkan, file lama di-backup).
- Lacak perintah panjang: tambahkan `eval "$(dylan shell-init zsh)"` ke `~/.zshrc`.
- `dylan doctor` mengecek app, socket, hook, dan shell integration. `dylan debug state` mencetak aktivitas yang sedang tampil.
- Build memakai signature ad-hoc, jadi macOS bisa meminta izin (Kalender, Automation) lagi setelah build baru. Untuk pemakaian harian, pakai build yang sama.
- `build/Dylan.app/Contents/MacOS/Dylan --snapshot <folder> --lang id|en` merender state notch ke PNG tanpa izin Screen Recording.

## Prinsip

Lokal, tanpa telemetry, gratis, ringan (idle < 1% CPU). Semua akses jaringan opt-in (GitHub, cuaca, lirik, Spotify). Fitur developer mati secara default dan tidak meminta izin apa pun sampai Mode Developer dinyalakan.

## Rencana stack

- Swift 6, SwiftUI + AppKit, SwiftPM
- macOS 15+ (efek glass di macOS 26+)
- Tanpa dependensi pihak ketiga di v1.0 (satu pengecualian opsional untuk media browser, lihat PRD §2.2)

## Lisensi

[MIT](LICENSE)
