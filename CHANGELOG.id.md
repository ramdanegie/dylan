# Catatan perubahan

Semua perubahan penting di Dylan. Dylan menampilkan bagian untuk versimu sekali setelah update (Settings → Tentang → Yang baru).

## [Unreleased]

### Diperbaiki
- Ikon app kembali ke "Pulau + telinga" (desain 4c); 0.1.6 keliru memakai ikon lain.

## [0.1.6] - 2026-11-04

### Ditambahkan
- Rekam layar: `⌥⇧5` atau Screenshot ▸ Rekam Layar, lalu seret area atau klik untuk seluruh layar. Disimpan sebagai MP4 di samping screenshot, dengan suara sistem dan, bila dinyalakan, mikrofon. Notch menampilkan titik merah dan waktunya; hentikan dari notch, menu, atau `⌥⇧5`.

### Diubah
- Tampilan baru Settings (desain D50): tiap halaman dibuka dengan banner pulau Dylan, judul serif, warna netral hangat, dan teal Cermin; grup berupa kartu putih. Optimasi Penyimpanan, update, dan riwayat capture ikut tampilan yang sama.
- Ikon app baru "Sirkuit".

## [0.1.5] - 2026-11-04

### Ditambahkan
- Optimasi Penyimpanan (menu bar, Settings → Penyimpanan): pindai cache, log, Downloads lama, file besar, cadangan iPhone, dan di Mode Developer data Xcode, cache paket, serta node_modules lama. Centang yang mau dihapus; tiap item menampilkan ukuran, lokasi, dan dampaknya. Yang dibuat ulang otomatis dihapus, file milikmu dipindah ke Trash.
- Peringatan di notch saat disk hampir penuh, dengan tombol Bersihkan.

### Diubah
- Sidebar Settings dikelompokkan per kegunaan: Notch, Sistem, Alat, Developer, Info.

## [0.1.4] - 2026-11-04

### Ditambahkan
- Tentang menampilkan pembuat, Egie Ramdan, dengan tautan ke GitHub dan source code (Settings → Tentang, dan "Tentang Dylan" di menu bar).

## [0.1.3] - 2026-11-04

### Ditambahkan
- Editor screenshot: setelah Simpan, notch menampilkan "Klik untuk membuka di Finder" dengan path file dan tombol Finder.

## [0.1.2] - 2026-11-04

### Ditambahkan
- Cek update: Dylan bisa mencari rilis baru di GitHub (Settings → Tentang), menampilkan catatan rilis, dan mengunduh DMG. Cek otomatis harian bersifat opt-in; tombol "Periksa sekarang" selalu ada.
- Yang baru: setelah update, Dylan menampilkan perubahan di versimu sekali.
- Hasil Face Unlock di notch: "Wajah · 09.12", lalu Peek dengan skor kecocokan, lama terkunci, dan tombol Riwayat. Pemberitahuan merah "Dimatikan" menjelaskan saat Face Unlock berhenti.

### Diubah
- Screenshot: setelah area dipilih, spinner langsung muncul dan editor terbuka tanpa jeda beku.
- Editor screenshot: Salin (⌘C) dan Simpan (⌘S) jadi ikon tepat setelah tombol jendela.
- Settings Face Unlock memberi tahu apakah sudah siap, atau kenapa belum (mis. izin Accessibility belum ada).

### Diperbaiki
- Face Unlock tidak lagi menunggu buka kunci dengan password setiap kali Dylan dibuka ulang (setelah Mac restart tetap wajib).
- "Coba kunci sekarang" juga mematikan layar, jadi kamera benar-benar menyala saat layar dibangunkan.

## [0.1.1] - 2026-11-04

### Ditambahkan
- Pendaftaran Face Unlock 4 langkah dengan preview kamera dan cincin progres 20 frame.
- Face Unlock punya menu sendiri di Settings.

### Diubah
- Crosshair dan loupe capture lebih mulus.
- Panah, kotak, dan sorot langsung terlihat saat drag.

### Diperbaiki
- Esc selalu membatalkan crosshair capture, termasuk saat shortcut ditekan dari app lain.

## [0.1.0] - 2026-11-04

Build uji pertama.

### Ditambahkan
- Notch sebagai pusat status: Compact, Peek, dan Expanded, dengan tab Home, Media, Shelf, Clipboard, Stats, dan Suhu.
- Musik (Spotify, Apple Music, tab browser, VLC), lirik, volume per app, equalizer langsung.
- Screenshot: area, jendela, layar, scroll, dan teks (OCR), editor anotasi dan Studio.
- Suhu dan kontrol kipas dengan helper root yang selalu mengembalikan kipas ke macOS.
- Notifikasi, panggilan, kontrol meeting, Discord, perangkat, dan bantuan sehari-hari.
- Mode Developer: agent AI (Claude Code, Codex, Cursor, OpenCode), command tracker, CLI Live Activity, port, GitHub, dan lainnya.
