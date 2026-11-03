# Dylan

**Dynamic Island untuk Mac, untuk semua orang, dengan Mode Developer opsional.**

Dylan mengubah notch MacBook menjadi pusat status yang hidup: musik, Discord, notifikasi, baterai, dan meeting muncul kecil di samping notch, lalu menyingkir sendiri setelah selesai. Fitur terbaik dari Droppy, Atoll, DynamicLake, dan Alcove digabung dalam satu app gratis.

> **Status:** tahap perencanaan. Belum ada kode. Spesifikasi lengkap ada di [PRD.md](PRD.md).

## Fitur yang direncanakan

**Untuk semua orang**
- **Musik:** kontrol penuh Spotify & Apple Music, putar playlist favorit, lirik tersinkron, media dari browser.
- **Discord:** siapa yang sedang bicara di voice, mute/deafen/keluar, DM & mention, langsung dari notch.
- **Notifikasi & pesan:** notifikasi app di notch, balas iMessage cepat, panggilan masuk.
- **Perangkat:** HUD volume/brightness, animasi charging, baterai AirPods, indikator kamera/mikrofon.
- **Produktivitas:** countdown meeting + Join, reminder, timer/Pomodoro, shelf file + AirDrop, clipboard, color picker, keep awake, cuaca.
- **Mode Presentasi:** sembunyikan isi sensitif saat screen share.

**Mode Developer (opsional)**
- **Agent AI:** status Claude Code (nanti Codex); izin bisa dijawab langsung dari notch.
- **Perintah panjang:** `npm test`, build, deploy. Notch memberi tahu saat selesai/gagal.
- **Dev harian:** dev server & port, status GitHub Actions, clipboard yang paham JWT/JSON/timestamp.

## Live Activity API

Script apa pun bisa menampilkan progres di notch lewat CLI `dylan`:

```bash
dylan activity start deploy --title "Deploy staging" --progress 0
dylan activity update deploy --progress 0.6 --subtitle "migrasi DB"
dylan activity end deploy --success --detail "v2.4.1 · 3m 10s"
```

## Prinsip

Lokal, tanpa telemetry, gratis, ringan (idle < 1% CPU). Semua akses jaringan opt-in (GitHub, cuaca, lirik, Spotify).

## Rencana stack

- Swift 6, SwiftUI + AppKit, SwiftPM
- macOS 15+ (efek glass di macOS 26+)
- Tanpa dependensi pihak ketiga di v1.0

## Lisensi

[MIT](LICENSE)
