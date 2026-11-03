# Spike T0.3 — Media

| Sumber | Cara | Status |
|---|---|---|
| Spotify | Distributed notification `com.spotify.client.PlaybackStateChanged` (judul, artis, album, posisi, durasi, track ID) + AppleScript untuk artwork URL, shuffle, repeat, volume, dan kontrol | Diimplementasikan. Kontrol butuh izin Automation (prompt muncul saat Dylan pertama mengontrol Spotify). Belum diuji live di sesi ini karena Spotify tidak berjalan. |
| Apple Music | Notification `com.apple.Music.playerInfo` (tanpa posisi) → satu query AppleScript untuk posisi, shuffle, repeat, volume, dan artwork (`raw data of artwork 1`) | Diimplementasikan, belum diuji live. |
| Browser (YouTube dll.) | MediaRemote lewat pendekatan `mediaremote-adapter` | **Belum dikerjakan.** Butuh menjalankan helper lewat `/usr/bin/perl` dan cek lisensi. Tetap opsional (FR-11). |

Keputusan:
- Tidak ada polling: posisi dihitung dari event terakhir selama lagu berputar.
- Dylan tidak pernah mengirim AppleScript ke app yang tidak berjalan (`tell application` akan membukanya).
- Artwork Spotify diambil dari CDN Spotify (`i.scdn.co`) satu kali per lagu. Ini akses jaringan yang belum tercantum di PRD §2.8; perlu dicatat di PRD atau dibuat opsional.
