# Dylan

**Dynamic Island untuk Mac, khusus software engineer.**

Dylan mengubah notch MacBook menjadi pusat status pekerjaan engineering: agent AI, perintah panjang, CI, dan meeting muncul kecil di samping notch, lalu menyingkir sendiri setelah selesai.

> **Status:** tahap perencanaan. Belum ada kode. Spesifikasi lengkap ada di [PRD.md](PRD.md).

## Fitur yang direncanakan

- **Agent AI:** status Claude Code (nanti Codex), notifikasi saat agent butuh izin atau selesai. Izin bisa dijawab langsung dari notch.
- **Perintah panjang:** `npm test`, build, migrasi, deploy. Notch memberi tahu saat selesai/gagal, lengkap dengan durasi dan exit code.
- **Meeting:** hitung mundur sebelum meeting, dengan tombol **Join**.
- **Dev harian:** dev server & port, status GitHub Actions, clipboard yang paham JWT/JSON/timestamp, shelf file.
- **Standar Dynamic Island:** Now Playing, timer/Pomodoro, stats sistem.
- **Mode Presentasi:** sembunyikan isi sensitif saat screen share.

## Live Activity API

Script apa pun bisa menampilkan progres di notch lewat CLI `dylan`:

```bash
dylan activity start deploy --title "Deploy staging" --progress 0
dylan activity update deploy --progress 0.6 --subtitle "migrasi DB"
dylan activity end deploy --success --detail "v2.4.1 · 3m 10s"
```

## Prinsip

Lokal, tanpa telemetry, gratis, ringan (idle < 1% CPU). Akses jaringan hanya untuk GitHub, dan itu opt-in.

## Rencana stack

- Swift 6, SwiftUI + AppKit, SwiftPM
- macOS 15+ (efek glass di macOS 26+)
- Tanpa dependensi pihak ketiga di v1.0

## Lisensi

[MIT](LICENSE)
