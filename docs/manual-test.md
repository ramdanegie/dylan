# Uji manual: fitur yang butuh izin, perangkat, atau layar terkunci

Semua yang bisa diuji tanpa izin baru sudah diuji (`docs/test-report.md`). Daftar ini butuh kamu karena memunculkan prompt izin macOS, butuh perangkat, atau butuh mengunci layar. Kolom status diisi dari sesi uji bersama. Jalankan dari build terbaru (`./scripts/build.sh --run`). Signature ad-hoc berubah tiap build, jadi beri izin Accessibility lagi setelah build ulang. `dylan debug state` menampilkan `"accessibility": true/false`.

| # | Fitur | Langkah | Hasil yang diharapkan | Status (4 Nov 2026) |
|---|---|---|---|---|
| 1 | Notifikasi (FR-68) | Settings → Live Activity → nyalakan "Notifikasi app" → Izinkan Accessibility. Jalankan `osascript -e 'display notification "halo" with title "Uji"'` | P1 di notch "Script Editor · Uji · halo". Kosongkan daftar app dulu, atau tambahkan "Script Editor" | **Lulus dari Dylan.app**: P1, digabung "· 3 messages", tidak ada isi di disk |
| 2 | Balas (FR-69) | Minta seseorang kirim WhatsApp/Pesan → klik Balas di Peek | Kolom balasan di banner macOS terbuka | Belum (butuh pesan asli) |
| 3 | Panggilan (FR-82) | Telepon FaceTime dari iPhone | P0 "… menelepon" dengan Tolak merah / Terima hijau; menjawab di iPhone membuat notch hilang | Belum (butuh iPhone) |
| 4 | Kontrol meeting (FR-83) | Gabung Zoom/Meet test call → Mic/Kamera/Share di Peek | Mic di Zoom berubah (menu Meeting); di Meet hanya saat tab Meet di depan | Pencarian menu & mask modifier diuji live (Finder); klik belum |
| 5 | Presentasi otomatis (FR-28) | Settings → nyalakan "Nyalakan otomatis saat share layar" → share layar di Zoom | Mode Presentasi menyala, lalu mati saat share berhenti | Belum (butuh share layar) |
| 6 | Pemutar lain (FR-11) | Nyalakan "Pemutar lain" → "Izinkan browser & VLC" → putar video YouTube di Chrome | Judul video di Media; play/pause lewat media key (minta izin post-event saat klik pertama) | Judul YouTube **lulus**. Media key tidak berfungsi di macOS 27.2 → tombol sekarang membawa tab ke depan (diuji di Chrome) |
| 7 | Equalizer langsung (FR-63) | Nyalakan "Equalizer mengikuti musik" → putar Spotify → izinkan rekam audio | Bar mengikuti musik; tanpa izin tetap animasi | Belum (izin rekam audio) |
| 8 | Volume per app (FR-84) | Nyalakan "Volume per app" → Media → tombol output → geser Chrome ke 30% | Chrome lebih pelan; 100% = tap dilepas; quit Dylan = suara normal lagi | Belum (izin rekam audio) |
| 9 | Waktunya berangkat (FR-81) | Nyalakan, izinkan Location, buat event 1 jam lagi dengan alamat fisik | P1 "Waktunya berangkat …" pada waktu mulai − perjalanan − 5 mnt | Location diizinkan; ETA Apple Maps lulus (Monas → Senayan 15 mnt). Alarm belum (butuh event Kalender) |
| 10 | Baterai AirPods (FR-44) | Nyalakan Bluetooth di Settings, sambungkan AirPods | "AirPods Pro · L 80% R 75% Case 40%" | Belum (butuh AirPods) |
| 11 | Focus (FR-72) | Nyalakan Jangan Ganggu di Control Center | P3 singkat "Jangan Ganggu aktif". Bila tidak muncul, beri Full Disk Access | Parser jalan di data asli; notch belum |
| 12 | Akun Spotify (FR-64) | Buat app di developer.spotify.com dengan Redirect URI `http://127.0.0.1:47823/callback`, tempel Client ID, Hubungkan | Playlist muncul di Settings; ♥ menyimpan lagu; "Berikutnya: …" di Media | Belum (butuh Client ID) |
| 13 | Terminal (FR-41) | Developer → nyalakan Terminal cepat → ⌃⌥T → `npm test` / `sleep 30` lalu ⌃C | Output tampil; ⌃C menghentikan; "Terminal" membuka folder yang sama | PTY diuji di unit test; tab belum |
| 14 | Widget lock screen (FR-80) | Nyalakan (eksperimental) → kunci layar sambil Spotify diputar | Jam/baterai/lagu di lock screen. Bila tidak muncul, fitur mati sendiri (spike T4.1) | Spike T4.1 **berhasil** (jendela uji tampil di lock screen); bug kode balik diperbaiki; panel Dylan belum dilihat |
| 15 | Face Unlock (FR-50–55) | **Di akun macOS uji**, bukan akun utama: daftar → kunci → nyalakan layar → ikuti instruksi suara | Terbuka; riwayat mencatat skor. Uji juga foto, orang lain, dan 5 kali gagal (spike T5.0) | Belum (akun macOS uji) |
