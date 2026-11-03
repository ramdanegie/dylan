# Dylan

**Dynamic Island untuk Mac. Untuk semua orang, dengan banyak fitur khusus engineer.**

Dylan mengubah notch MacBook menjadi pusat status yang hidup: musik, Discord, notifikasi, baterai, dan meeting muncul kecil di samping notch, lalu menyingkir sendiri setelah selesai. Fitur terbaik dari Droppy, Atoll, DynamicLake, dan Alcove digabung dalam satu app gratis.

Buat software engineer, Dylan punya **Mode Developer**: pantau agent AI, perintah panjang, CI, dan dev server langsung dari notch. Pengguna biasa tidak akan melihat fitur ini sama sekali; engineer cukup menyalakannya sekali.

> **Status:** tahap perencanaan. Belum ada kode. Spesifikasi lengkap ada di [PRD.md](PRD.md).

## Fitur untuk semua orang

- **Musik:** kontrol penuh Spotify & Apple Music (shuffle, repeat, volume, love), putar playlist favorit sekali klik, lirik tersinkron, media dari browser (YouTube dll.), pilih output audio.
- **Discord:** siapa yang sedang bicara di voice, mute/deafen/keluar, DM & mention, langsung dari notch.
- **Notifikasi & pesan:** notifikasi app di notch, balas iMessage cepat, panggilan masuk, kontrol mute/kamera saat meeting.
- **Perangkat:** HUD volume/brightness, animasi charging, baterai AirPods, indikator kamera/mikrofon, Focus.
- **Produktivitas:** countdown meeting + tombol Join, reminder, timer/Pomodoro, shelf file + AirDrop, clipboard, color picker, keep awake, cuaca, progres download.
- **Mode Presentasi:** sembunyikan isi sensitif saat screen share.
- **Bahasa Indonesia & English:** pilih di Settings, atau ikuti bahasa sistem.

## Fitur untuk engineer (Mode Developer)

- **Agent AI:** status Claude Code (tool & file yang sedang dikerjakan), notifikasi saat agent butuh izin atau selesai, lengkap dengan durasi dan `+x −y` baris. Izin bisa dijawab langsung dari notch. Codex CLI menyusul.
- **Command tracker:** `npm test`, build, migrasi, deploy. Notch memberi tahu saat selesai/gagal, lengkap dengan durasi dan exit code.
- **Live Activity API:** script apa pun bisa menampilkan progres di notch lewat CLI `dylan` (contoh di bawah).
- **Dev server & port:** port mana dipakai project apa, buka di browser, atau matikan.
- **GitHub:** status GitHub Actions di branch yang sedang dikerjakan dan jumlah PR yang menunggu review-mu.
- **Clipboard developer:** decode JWT, pretty-print JSON, Unix timestamp ↔ tanggal, Base64, UUID, hash. Token dan password otomatis disamarkan dan tidak pernah disimpan ke disk.
- **Stats + alert:** CPU, memori, jaringan; peringatan saat proses seperti `node` atau `docker` nyangkut memakan CPU.
- **Script widget, Docker, terminal di notch, MCP server** untuk Claude Code.
- **Touch ID untuk `sudo`.**

## Live Activity API

```bash
dylan activity start deploy --title "Deploy staging" --progress 0
dylan activity update deploy --progress 0.6 --subtitle "migrasi DB"
dylan activity end deploy --success --detail "v2.4.1 · 3m 10s"
```

## Prinsip

Lokal, tanpa telemetry, gratis, ringan (idle < 1% CPU). Semua akses jaringan opt-in (GitHub, cuaca, lirik, Spotify). Fitur developer mati secara default dan tidak meminta izin apa pun sampai Mode Developer dinyalakan.

## Rencana stack

- Swift 6, SwiftUI + AppKit, SwiftPM
- macOS 15+ (efek glass di macOS 26+)
- Tanpa dependensi pihak ketiga di v1.0 (satu pengecualian opsional untuk media browser, lihat PRD §2.2)

## Lisensi

[MIT](LICENSE)
