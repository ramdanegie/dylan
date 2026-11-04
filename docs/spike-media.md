# Spike T0.3 — Media

| Sumber | Cara | Status |
|---|---|---|
| Spotify | Distributed notification `com.spotify.client.PlaybackStateChanged` (judul, artis, album, posisi, durasi, track ID) + AppleScript untuk artwork URL, shuffle, repeat, volume, dan kontrol | Diimplementasikan. Kontrol butuh izin Automation (prompt muncul saat Dylan pertama mengontrol Spotify). Belum diuji live di sesi ini karena Spotify tidak berjalan. |
| Apple Music | Notification `com.apple.Music.playerInfo` (tanpa posisi) → satu query AppleScript untuk posisi, shuffle, repeat, volume, dan artwork (`raw data of artwork 1`) | Diimplementasikan, belum diuji live. |
| Browser (YouTube, YouTube Music, SoundCloud, Spotify Web, Twitch, Netflix) & VLC | Tanpa MediaRemote. Core Audio: browser mana yang bersuara. AppleScript: judul + URL tab (Chrome, Safari, Arc, Edge, Brave, Vivaldi) atau item VLC. Kontrol: media key sistem (play/next/prev ke app Now Playing), VLC lewat AppleScript | Diimplementasikan (opt-in). Firefox tidak punya AppleScript tab, jadi tidak didukung. Tanpa artwork, posisi, atau seek untuk browser. `mediaremote-adapter` (API privat lewat `/usr/bin/perl`) tidak dipakai. |

Keputusan:
- Tidak ada polling: posisi dihitung dari event terakhir selama lagu berputar.
- Dylan tidak pernah mengirim AppleScript ke app yang tidak berjalan (`tell application` akan membukanya).
- Artwork Spotify diambil dari CDN Spotify (`i.scdn.co`) satu kali per lagu. Ini akses jaringan yang belum tercantum di PRD §2.8; perlu dicatat di PRD atau dibuat opsional.
