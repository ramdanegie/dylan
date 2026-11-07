# Catatan perubahan

Semua perubahan penting di Dylan. Dylan menampilkan bagian untuk versimu sekali setelah update (Settings → Tentang → Yang baru).

## [Unreleased]

### Diperbaiki
- Face Unlock membaca gerak kepala dengan presisi. Sebelumnya kiri dan kanan melompat per 45° dan atas atau bawah tidak pernah terbaca, jadi pendaftaran lama dan "lihat ke atas" tidak pernah bisa lolos. Arah kiri dan atas kini dipelajari dari gerakanmu sendiri saat mendaftar atau menambah identitas.
- Pengetikan password di lock screen: island ditutup dulu, password diketik satu karakter demi satu, dan Return ditekan setelah jeda singkat. Saat diuji, tantangan yang lolos tetap membuat Mac terkunci.
- Membuka kunci manual setelah percobaan gagal tidak lagi tercatat sebagai dibuka dengan wajah.
- Cek layar HP atau tablet tidak lagi salah menangkap wajah asli di depan pintu atau monitor.

### Diubah
- Pendaftaran cukup lima arah (lurus, kiri, kanan, atas, bawah), bukan sembilan. Cukup menoleh sekitar 10° dari posisi awal, dan titik kepala bergerak halus.
- Tantangan mengucapkan "pejamkan mata sebentar", bukan "kedip": kedipan cepat bisa jatuh di antara frame kamera.

### Ditambahkan
- Latihan tantangan (Settings → Face Unlock → Uji wajah): tantangan yang sama saat Mac tidak terkunci, dengan hasil dan apa yang dilihat kamera. Tidak ada yang diketik atau dihitung.
- Salin riwayat. Tiap percobaan juga menampilkan seberapa jauh kamu menoleh, seberapa rapat matamu terpejam, dan skornya.

## [0.3.0] - 2026-11-07

### Ditambahkan
- Face Unlock, terinspirasi Glance:
  - Identitas wajah: tambah hingga lima tampilan (kacamata, masker, cahaya redup, atau orang yang kamu percaya), masing-masing bisa dimatikan tanpa dihapus.
  - Pendaftaran terpandu: satu busur untuk tiap sembilan arah kepala, titik yang mengikuti kepalamu, dan "kembali sedikit" saat menoleh terlalu jauh.
  - Island scan di lock screen berisi gerakan yang harus dilakukan, lalu centang atau silang (eksperimental; bila macOS menolak, instruksi diucapkan).
  - Tekan spasi di lock screen untuk coba lagi (butuh Input Monitoring; mati sampai kamu nyalakan).
  - Uji wajah: kamera 10 detik dengan skor tiap identitas. Tidak membuka apa pun dan tidak menyimpan apa pun.
  - Ganti password tersimpan tanpa mendaftar ulang.
  - Ketukan trackpad saat berhasil atau gagal.

### Diubah
- Face Unlock memaafkan frame buram hingga total 1,5 detik alih-alih langsung gagal (kedipan tetap harus wajahmu), dan gagal bila layar HP atau tablet membingkai wajahmu.
- Menyalakan Face Unlock, batas kunci lebih lama, menambah atau menyalakan identitas, password baru, dan spasi untuk coba lagi meminta Touch ID dulu. Mematikan tidak pernah meminta.
- Pendaftaranmu yang sekarang menjadi identitas "Wajah utama"; tidak perlu mendaftar ulang.

## [0.2.1] - 2026-11-05

### Ditambahkan
- Waktu salat bisa mengikuti lokasi saat ini (Settings → Waktu salat → Pakai lokasi saat ini): tidak perlu mengetik kota, dan jadwal ikut berubah saat bepergian. Lokasi dibulatkan sekitar 1 km dan tetap di Mac-mu.

### Diubah
- Gaya island Warna dimulai dari hitam.

## [0.2.0] - 2026-11-05

### Ditambahkan
- Waktu salat (Settings → Waktu salat): jadwal Kemenag untuk kotamu, dihitung di Mac. Hitung mundur di notch 30 menit sebelum salat, Peek saat waktunya, tab Salat dengan tanggal Hijriah, pengingat 5–30 menit sebelumnya, dan azan dari file audio pilihanmu dengan musik dijeda lalu dilanjutkan.
- Fokus: durasi Pomodoro bisa diatur, istirahat mulai sendiri dengan tombol Lewati, dan stopwatch dengan lap.
- Lirik: karaoke bila liriknya punya timing per kata, romanisasi untuk Korea, Jepang, Mandarin, Thai, dan Arab, serta terjemahan ke bahasamu (Apple Translation).
- Notifikasi: tab Notifikasi berisi riwayat hari ini (atau 7 hari) per percakapan, plus opsi island tenang saat Focus (pesan hanya dihitung di telinga).
- Drop actions: seret file ke tepi atas lalu lepas di Shelf, Kompres, AirDrop, iCloud Drive (dan folder cloud lain yang tersinkron), atau Bagikan; gambar juga bisa Hapus background dan Ubah ukuran.
- Gaya island: hitam, warna, kaca, kaca buram, atau pulau melayang. Di layar tanpa notch, pill bisa digeser di tepi atas dan bisa menyingkir saat kursor hanya lewat.
- Modul Home (Edit modul): tugas hari ini, flashcard dengan pengulangan berjarak (impor CSV atau Anki), dan radio internet.
- Mik mati untuk semua app (`⌃⌥M`) dan mode pesawat (`⌃⌥⇧A`, Wi‑Fi mati lalu nyala lagi), di Settings → Perangkat.
- Animasi satu per satu (Settings → Animasi): garis cahaya di island untuk notifikasi, garis waktu, notifikasi bertumpuk, dan konfeti saat tugas hari itu selesai.

### Diubah
- Ikon menu bar baru dari ikon app: pulau dengan dua telinga, solid saat ada yang berjalan, titik saat ada yang butuh tindakanmu, dicoret saat Mode Presentasi.

## [0.1.7] - 2026-11-04

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
