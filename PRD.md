# PRD — Dylan: Dynamic Island untuk Mac (untuk semua orang, plus Mode Developer)

| Field | Isi |
|---|---|
| Nama produk (kerja) | **Dylan** (*DY*namic is*LAN*d; boleh diganti) |
| Platform | macOS native (Swift 6 + SwiftUI/AppKit), macOS 15+, dioptimalkan untuk macOS 26+ |
| Perangkat utama | MacBook Pro 14" M1 Pro (ada notch, ProMotion 120 Hz), macOS 27 |
| Versi dokumen | 1.1 (1.0 → 1.1: lingkup diperluas ke pengguna umum; fitur terbaik Droppy, Atoll, DynamicLake, Alcove ditambahkan) |
| Tanggal | 3 November 2026 |
| Owner | Egie |
| Status | Draft → siap untuk Claude Design → Claude Code |
| Alur kerja | **PRD (dokumen ini) → Claude Design (Bagian 3) → Claude Code (Bagian 4)** |

---

## Daftar Isi

1. **Bagian 1 — PRD**: masalah, tujuan, persona, lingkup, requirement, metrik, risiko, referensi kompetitor (Droppy, Atoll, DynamicLake, Alcove)
2. **Bagian 2 — Spec Fitur & Teknis**: arsitektur, stack, model notch, spec per fitur, bridge & CLI, izin, privasi
3. **Bagian 3 — Design Brief** (untuk Claude Design)
4. **Bagian 4 — Task Breakdown** (untuk Claude Code) + prompt pembuka
5. **Bagian 5 — Checklist Uji Manual**

---

# BAGIAN 1 — PRD

## 1.1 Ringkasan (TL;DR)

Dylan mengubah notch MacBook menjadi **pusat status yang hidup untuk semua pengguna Mac**, dengan **Mode Developer** opsional untuk software engineer. Hal yang biasanya membuatmu bolak-balik pindah jendela muncul kecil di samping notch, lalu menyingkir sendiri setelah selesai.

**Untuk semua orang:**
- **Musik:** kontrol penuh Spotify & Apple Music (play/pause, next, seek, shuffle, repeat, volume, putar playlist favorit), lirik tersinkron, media dari browser (YouTube dll.), visualizer yang mengikuti warna artwork.
- **Discord:** status voice channel (siapa yang bicara), tombol mute/deafen/keluar, dan DM/mention masuk, langsung dari notch.
- **Notifikasi & pesan:** notifikasi app tampil di notch; balas iMessage cepat.
- **HUD & perangkat:** pengganti HUD volume/brightness/backlight keyboard, animasi charging + baterai, AirPods/Bluetooth tersambung lengkap dengan baterai, indikator kamera/mikrofon sedang dipakai, indikator Focus.
- **Meeting & produktivitas:** hitung mundur meeting dengan tombol **Join**, agenda + reminder, timer/Pomodoro, shelf file + AirDrop, clipboard history, color picker, keep awake, cuaca, scratchpad, progres download.
- **Standar Dynamic Island:** Live Activity ganda (Duo), gestur swipe, pill untuk layar tanpa notch, tema (termasuk Liquid Glass).

**Mode Developer (opsional):**
- **Agent AI:** apa yang sedang dikerjakan Claude Code (dan nanti Codex), kapan agent **butuh izin**, dan kapan **selesai**. Izin bisa dijawab langsung dari notch.
- **Perintah panjang:** `npm test`, build, migrasi, deploy. Notch memberi tahu saat perintah selesai atau gagal, lengkap dengan durasi dan exit code.
- **Dev harian:** dev server yang jalan di port mana, status GitHub Actions di branch-mu, clipboard yang paham JWT/JSON/timestamp, stats sistem + alert proses boros.

**Eksperimental:**
- **Face Unlock:** membuka kunci Mac dengan wajah lewat kamera FaceTime, dengan batasan keamanan ketat dan hanya bila spike membuktikan bisa (§F15). Ditambah alternatif yang lebih aman: **Touch ID untuk `sudo`** (§F16).

Pembeda utama: **semua fitur bagus dari Droppy, Atoll, DynamicLake, dan Alcove dalam satu app gratis**, ditambah **Live Activity API terbuka** lewat CLI `dylan`. Script apa pun bisa menampilkan progres di notch:

```bash
dylan activity start deploy --title "Deploy staging" --progress 0
dylan activity update deploy --progress 0.6 --subtitle "migrasi DB"
dylan activity end deploy --success --detail "v2.4.1 · 3m 10s"
```

Prinsip: **lokal, tanpa telemetry, gratis, ringan** (idle < 1% CPU), dan **aman saat screen share** lewat Mode Presentasi.

## 1.2 Latar Belakang & Masalah

1. **Notch adalah ruang mati.** Di MacBook Pro 14", area sekitar notch hanya berisi menu bar yang terpotong.
2. **Hal kecil sehari-hari memaksa pindah app:** ganti lagu di Spotify, mute di voice Discord, cek siapa yang sedang bicara, melihat baterai AirPods, membaca notifikasi yang lewat terlalu cepat. HUD volume/brightness bawaan macOS menutupi tengah layar.
3. **Engineer banyak menunggu proses di background:** agent AI, test, build, CI, deploy. Untuk mengecek, kamu harus pindah ke terminal atau browser. Kalau lupa mengecek, Claude Code bisa menunggu izin 20 menit di terminal VS Code yang tertutup jendela lain.
4. **Meeting terlewat** saat sedang fokus bekerja.
5. **Fitur bagus tersebar di beberapa app, dan sebagian berbayar:**
   - Alcove punya polish terbaik, DynamicLake punya plugin, keduanya berbayar.
   - Droppy paling lengkap (44 "droplet", termasuk balas pesan dan coding agent), tapi berbayar.
   - Atoll gratis dan open-source, tapi berlisensi GPL-3.0.
   - Tidak ada satu app yang menggabungkan semuanya, plus integrasi Discord dan alat developer.
6. **Risiko saat screen share:** notch yang menampilkan isi clipboard, nama file, atau judul meeting bisa ikut terlihat peserta. Ini penting saat demo aplikasi telemedicine.

## 1.3 Tujuan & Non-Tujuan

### Tujuan
1. **Musik, Discord, notifikasi, dan perangkat** bisa dikontrol dan dibaca dari notch tanpa pindah app.
2. Status agent AI, perintah panjang, dan CI terbaca dalam **satu lirikan** (Mode Developer).
3. **Tidak pernah melewatkan** meeting, mention Discord, atau permission prompt agent.
4. Mempercepat pekerjaan kecil harian: shelf file, clipboard, color picker, timer, keep awake (+ dev tools di Mode Developer).
5. Terasa **native dan halus** seperti Dynamic Island iPhone, dengan standar polish Alcove.
6. **Satu app gratis yang menggabungkan fitur terbaik** keempat referensi (§1.12), tanpa menyalin kode GPL.
7. **Ringan, privat, offline-first.** Semua akses jaringan opt-in (GitHub, cuaca, lirik, Spotify Web API).
8. **Tetap sederhana untuk pengguna umum:** fitur developer mati secara default dan baru muncul saat Mode Developer dinyalakan.

### Non-Tujuan (tidak dikerjakan)
- "Face ID" yang setara iPhone. Mac tidak punya kamera TrueDepth (inframerah + kedalaman), jadi Face Unlock di Dylan hanya pengenalan wajah 2D dan **lebih lemah dari Touch ID maupun password** (§F15).
- Kontrol Apple TV (butuh protokol privat), suara keyboard mekanik, uninstaller app, dan window snapping. Semuanya di luar fungsi notch, dan sudah ada app khusus yang lebih baik (mis. Rectangle untuk window snapping).
- Membaca isi chat WhatsApp/Telegram/Slack langsung dari database app. Dylan hanya memakai notifikasi yang memang ditampilkan macOS (§F18).
- App pendamping iPhone, sinkronisasi cloud, akun, lisensi berbayar.
- Plugin marketplace. Penggantinya Live Activity API + script widget, yang jauh lebih sederhana.
- Pelacakan kuota AI (usage Claude/Codex), karena sudah ditangani **CodexBar** yang terpasang.
- Menggantikan terminal atau IDE.
- Distribusi Mac App Store. App Store butuh sandbox, sedangkan Dylan perlu membaca `~/.claude`, menjalankan `lsof`, dan sejenisnya.

## 1.4 Target Pengguna & Persona

**Persona utama: Egie, software engineer di perusahaan health-tech (telemedicine)**
- Mac: MacBook Pro 14" M1 Pro (notch, ProMotion 120 Hz), macOS 27.
- Tools: Claude Code dan Codex CLI, VS Code dan Zed (pakai terminal terintegrasinya), zsh, Docker, GitHub CLI (`gh`), Node.js, TablePlus, Chrome, Spotify, Zoom.
- Pola kerja: beberapa sesi Claude Code paralel, menunggu test/build, review PR, meeting Zoom, sering screen share saat demo.

**Persona kedua: pengguna umum (mahasiswa, desainer, kreator, pekerja kantor)**
- Mac: MacBook Air/Pro dengan notch, atau Mac dengan monitor eksternal.
- Tools: Spotify atau Apple Music, Discord (kuliah, komunitas, main game bareng), Chrome/Safari (YouTube), iMessage/WhatsApp, AirPods, Kalender, Figma/Canva.
- Pola kerja: musik hampir selalu menyala, sering di voice Discord sambil bekerja/belajar, banyak menyalin warna dan file, ingin Mac terasa "seperti iPhone".
- Tidak butuh terminal; fitur developer tidak boleh muncul atau meminta izin.

**Persona ketiga:** engineer lain dengan pola kerja seperti Egie, bila Dylan dibuka sebagai open-source.

## 1.5 User Stories

US-1 s/d US-15 ditulis dari sudut pandang engineer (Mode Developer), kecuali US-6, US-7, US-9, dan US-12 yang berlaku untuk semua orang. US-16 dan seterusnya untuk semua pengguna.

| ID | Sebagai pengguna, saya ingin… | supaya… |
|---|---|---|
| US-1 | melihat apa yang sedang dikerjakan Claude Code (tool, file) dari notch | tidak perlu membuka terminal untuk mengecek |
| US-2 | diberi tahu saat Claude Code butuh izin, dan bisa menjawab dari notch | agent tidak menganggur lama |
| US-3 | tahu saat agent selesai, berapa lama, dan berapa baris berubah | bisa langsung review |
| US-4 | diberi tahu saat perintah terminal yang lama selesai atau gagal | tidak perlu memantau terminal |
| US-5 | menampilkan progres script saya sendiri di notch | deploy/migrasi terpantau tanpa membuka terminal |
| US-6 | melihat hitung mundur meeting dan join dengan satu klik | tidak telat meeting |
| US-7 | mengontrol Spotify dari notch | tidak pindah app saat fokus |
| US-8 | melihat riwayat clipboard dan langsung men-decode JWT/JSON/timestamp | debug lebih cepat |
| US-9 | menaruh file sementara di notch lalu men-drag-nya ke tempat lain | memindah file antar jendela/Space lebih mudah |
| US-10 | melihat dev server yang jalan (port, project) dan mematikannya | tidak bingung "port 3000 dipakai siapa" |
| US-11 | tahu status GitHub Actions di branch saya dan PR yang menunggu review saya | CI gagal langsung ketahuan |
| US-12 | menyembunyikan isi sensitif notch saat screen share | data pasien/token tidak bocor saat demo |
| US-13 | diberi tahu bila ada proses yang memakan CPU berlebihan | laptop tidak panas tanpa sebab |
| US-14 | membuka kunci Mac hanya dengan melihat ke layar saat kembali ke meja | tidak perlu mengetik password atau menyentuh Touch ID |
| US-15 | memakai Touch ID untuk `sudo` di terminal | tidak mengetik password berkali-kali |
| US-16 | memutar playlist Spotify favorit, mengatur shuffle/repeat/volume, dan melihat lirik dari notch | tidak perlu membuka jendela Spotify |
| US-17 | mengontrol YouTube/media browser dari notch | kontrol yang sama untuk semua sumber audio |
| US-18 | melihat siapa yang sedang bicara di voice Discord, lalu mute/deafen/keluar dari notch | tidak perlu mencari jendela Discord saat sedang main game atau kerja |
| US-19 | diberi tahu DM/mention Discord dan notifikasi app lain di notch | tidak ketinggalan pesan penting, tanpa banner yang menutupi kerja |
| US-20 | membalas iMessage singkat dari notch | percakapan cepat tanpa pindah app |
| US-21 | melihat HUD volume/brightness yang rapi di notch | HUD bawaan tidak menutupi tengah layar |
| US-22 | melihat baterai AirPods/perangkat Bluetooth saat tersambung, dan animasi charging saat charger dicolok | tahu kondisi baterai tanpa membuka menu |
| US-23 | tahu saat kamera atau mikrofon sedang dipakai, dan saat Focus menyala | privasi dan konteks selalu terlihat |
| US-24 | mengambil warna dari layar dan menyalin hex/RGB | desain lebih cepat |
| US-25 | menahan Mac supaya tidak sleep selama download/presentasi | tidak perlu app terpisah |
| US-26 | melihat cuaca, reminder hari ini, dan progres download dari notch | informasi kecil sehari-hari ada di satu tempat |
| US-27 | melihat musik dan baterai di lock screen | tidak perlu membuka kunci hanya untuk ganti lagu |
| US-28 | menghapus background foto yang di-drop ke shelf | edit cepat tanpa app editor |
| US-29 | memilih bahasa Dylan (Indonesia atau English) | app nyaman dipakai, juga oleh teman yang tidak berbahasa Indonesia |

## 1.6 Lingkup per Rilis

Fitur bertanda **[Dev]** hanya aktif bila Mode Developer dinyalakan (FR-17). Sisanya untuk semua orang.

| Rilis | Tema | Isi |
|---|---|---|
| **v1.0 MVP** | Notch + Essentials | Shell notch (Compact/Peek/Expanded), Live Activity engine, CLI `dylan`, profil Umum/Developer, bahasa Indonesia/English, Now Playing+ (Spotify & Music lengkap, media browser bila spike berhasil), meeting berikutnya, timer/Pomodoro, baterai & charging, AirPods/Bluetooth, indikator kamera/mikrofon, Mode Presentasi, Settings & onboarding. **[Dev]** Claude Code, command tracker zsh |
| **v1.1** | Everyday + Discord | Discord (voice + DM/mention), lirik tersinkron, pilih output audio, volume per app, HUD volume/brightness/backlight, shelf file + AirDrop, clipboard history, color picker, keep awake, Focus, tema & kustomisasi, layar tanpa notch/monitor eksternal, stats. **[Dev]** dev tools clipboard, dev server/port, alert proses boros, Touch ID untuk `sudo` |
| **v1.2** | Notifikasi & Integrasi | Notifikasi app di notch, balas pesan (iMessage, WhatsApp/Telegram bila bisa), panggilan masuk, kontrol meeting, reminder + tambah cepat, cuaca, progres download. **[Dev]** GitHub Actions & PR, script widget, Codex CLI, Docker |
| **v1.3** | Ekstra (Could) | Visualizer audio nyata, like lagu & daftar playlist Spotify (Web API), transform file + hapus background, floating basket, OCR, scratchpad, kamera cermin, "waktunya berangkat", widget lock screen (eksperimental). **[Dev]** terminal cepat di notch, MCP server |
| **v2.0** | Face Unlock (eksperimental) | Buka kunci dengan wajah, **hanya bila spike T5.0 = Go**. Opt-in, mati secara default |

## 1.7 Requirement Fungsional (MoSCoW)

### v1.0 — Notch + Essentials (MVP)

| ID | Requirement | Prioritas |
|---|---|---|
| FR-1 | **Jendela notch:** bentuk hitam yang menyatu dengan notch. Posisi dan ukuran dihitung dari geometri layar (§2.4), tidak di-hard-code | Must |
| FR-2 | **Empat state:** Closed (tak terlihat, seukuran notch) · Compact (live activity di "telinga" kiri/kanan notch) · Peek (saat hover: sedikit membesar, detail aktivitas teratas) · Expanded (panel dengan tab) | Must |
| FR-3 | **Interaksi:** hover → Peek (delay 150 ms, bisa diatur); klik → Expanded; swipe dua jari ke bawah/atas → buka/tutup; hotkey global ⌃⌥Space; Esc atau klik di luar → tutup. Tidak pernah mencuri fokus keyboard, kecuali saat mengetik di kolom pencarian Dylan | Must |
| FR-4 | **Live Activity engine:** prioritas P0–P3 (§2.4); maksimal 2 aktivitas tampil bersamaan (Duo), sisanya antre; hasil (selesai/gagal) tampil 5 detik lalu masuk riwayat (20 terakhir) | Must |
| FR-5 | **Fullscreen:** notch disembunyikan saat app di depan sedang fullscreen; hanya P0 (agent butuh izin, meeting mulai) yang tetap muncul | Must |
| FR-6 | **CLI `dylan` + Live Activity API:** `activity start/update/end`, `notify`, `run -- <cmd>`, `doctor` (§2.6) | Must |
| FR-7 | **[Dev] Claude Code:** daftar sesi aktif (nama project, durasi); status bekerja (tool + file/perintah terkini), butuh izin, menunggu input, selesai (durasi, ringkasan, `+x −y` baris), gagal. Klik → fokus ke app terminal/editor tempat sesi berjalan | Must |
| FR-8 | **[Dev] Pasang hook sekali klik:** gabungkan ke `~/.claude/settings.json` tanpa menyentuh hook lain; backup dulu; tampilkan diff; idempotent; bisa dilepas lagi | Must |
| FR-9 | **[Dev] Jawab izin dari notch:** Izinkan / Tolak / Buka terminal, opt-in. Tidak boleh menahan prompt di terminal saat user sedang di terminal (§F3) | Should |
| FR-10 | **[Dev] Command tracker (zsh):** perintah yang berjalan > 10 detik tampil sebagai aktivitas; saat selesai tampil ✓/✗ + exit code + durasi; ada daftar abaikan (vim, ssh, `npm run dev`, dll.) | Must |
| FR-11 | **Now Playing:** Spotify & Apple Music (wajib), player lain (YouTube/Chrome/Safari, Podcasts, VLC) bila MediaRemote tersedia (spike T0.3). Artwork, judul, play/pause/next/prev, seek. Compact: artwork + equalizer | Must |
| FR-60 | **Now Playing+:** shuffle, repeat, slider volume, love/favorit (Apple Music lewat AppleScript); **putar cepat** playlist/album yang di-pin (Spotify dibuka otomatis bila belum jalan); "lanjutkan terakhir" saat tidak ada yang diputar; warna aksen dan glow dari artwork; sembunyi otomatis setelah pause > 5 menit (bisa diatur) | Must |
| FR-12 | **Meeting berikutnya:** dari app Kalender macOS. Hitung mundur mulai 10 menit sebelum; tombol Join untuk link Zoom/Meet/Teams; jadi P0 saat 1 menit sebelum | Must |
| FR-13 | **Timer & Pomodoro:** timer cepat (preset + custom) dan Pomodoro 25/5 dengan hitungan siklus; tetap akurat setelah sleep | Should |
| FR-14 | **Tab Home:** Now Playing + agenda hari ini + timer + baterai/perangkat; ringkasan agent/command yang sedang jalan bila Mode Developer aktif | Must |
| FR-15 | **Settings, onboarding, login item**, ikon menu bar (opsional) | Must |
| FR-16 | **Mode Presentasi:** toggle lewat hotkey ⌃⌥⌘H dan menu; saat aktif, isi sensitif disembunyikan (§F12) | Must |
| FR-17 | **Profil Umum / Developer:** dipilih di onboarding, bisa diganti kapan saja. Profil Umum (default) menyembunyikan semua fitur [Dev] beserta tab, izin, dan langkah onboarding-nya. Mode Developer menyalakan tab Agents & Dev, hook Claude Code, dan shell integration | Must |
| FR-18 | **Bahasa:** menu Settings → Umum → Bahasa: Ikuti sistem (default) / Bahasa Indonesia / English. Juga dipilih di langkah pertama onboarding. Berlaku untuk notch, Settings, onboarding, menu bar, dan notifikasi Dylan (§F14) | Must |
| FR-70 | **Baterai & charging:** animasi saat charger dicolok (persentase + perkiraan waktu penuh), saat dicabut, saat penuh; peringatan 20% dan 10%; ikon Low Power Mode | Must |
| FR-44 | **AirPods & Bluetooth:** animasi saat perangkat tersambung/terputus (nama + ikon jenis perangkat); baterai kiri/kanan/case bila tersedia (spike T0.6) | Should |
| FR-71 | **Indikator kamera & mikrofon:** titik hijau (kamera) / oranye (mikrofon) di telinga notch selama dipakai app mana pun; Peek menampilkan "Kamera sedang dipakai" | Should |

### v1.1 — Everyday + Discord

| ID | Requirement | Prioritas |
|---|---|---|
| FR-65 | **Discord voice:** saat kamu di voice channel: nama server/channel, peserta dengan indikator sedang bicara, status mute/deafen-mu. Aksi: mute, deafen, keluar. Compact: ikon mic + avatar yang sedang bicara (§F17) | Must |
| FR-66 | **Discord DM & mention:** pesan baru → P1 (pengirim, channel, cuplikan); klik → buka Discord di channel itu | Should |
| FR-67 | **Discord tanpa RPC (cadangan):** bila RPC tidak tersedia, tampilkan "Discord sedang memakai mikrofon" dan kirim mute/deafen lewat keybind Discord yang diatur user (§F17) | Should |
| FR-62 | **Lirik tersinkron:** baris lirik saat ini di Peek/Expanded, opsional berjalan di Compact; sumber LRCLIB (gratis, tanpa API key), cache lokal; opt-in karena memakai jaringan | Should |
| FR-61 | **Pilih output audio:** daftar perangkat output (speaker, AirPods, HDMI, AirPlay bila muncul sebagai device), ganti dengan satu klik | Should |
| FR-84 | **Volume per app:** mixer sederhana (Spotify, browser, Discord, Zoom) lewat Core Audio process tap (macOS 14.2+) | Could |
| FR-40 | **HUD volume/brightness/backlight keyboard** di notch, menggantikan HUD sistem (butuh Accessibility, spike T2.9) | Should |
| FR-73 | **Color picker:** ambil warna dari layar (`NSColorSampler`); salin hex/RGB/HSL; riwayat 20 warna; format SwiftUI/CSS di Mode Developer | Should |
| FR-74 | **Keep awake:** tahan Mac supaya tidak sleep: 15 m / 1 j / sampai dimatikan / sampai download selesai. Indikator cangkir di Compact | Should |
| FR-72 | **Focus:** aktivitas singkat saat Focus menyala/mati (nama Focus bila tersedia) | Could |
| FR-78 | **Tema & kustomisasi:** aksen dari artwork, ukuran notch, tema Liquid Glass untuk pill (macOS 26+), urutan & on/off tab, sembunyikan notch saat app tertentu di depan | Should |
| FR-20 | **Clipboard history:** teks, gambar, file; cari; pin. Klik = salin; ⏎ = salin + tempel (bila izin Accessibility diberikan) | Must |
| FR-21 | **[Dev] Smart detect + dev tools:** JSON (pretty/minify), JWT (decode header/payload, `exp` jadi waktu lokal), Unix timestamp ↔ tanggal, Base64, URL encode/decode, UUID, warna hex, path file, URL. Ditambah generator UUID, timestamp sekarang, dan hash | Must |
| FR-22 | **Proteksi rahasia:** abaikan item bertanda concealed/transient (password manager) dan app tertentu; item yang cocok pola token (§2.8) tidak disimpan ke disk, disamarkan, dan hilang setelah 2 menit | Must |
| FR-23 | **Shelf file:** drag file ke notch untuk disimpan; drag keluar ke mana pun; Quick Look, salin path, buka di editor, AirDrop, zip | Must |
| FR-24 | Screenshot baru otomatis masuk shelf | Should |
| FR-25 | **[Dev] Dev server/port:** daftar port TCP yang listen milik user (port, proses, folder project); buka di browser, salin URL, matikan (dengan konfirmasi); aktivitas singkat "localhost:3000 siap" saat server baru muncul | Must |
| FR-26 | **Stats:** CPU, GPU, memori, jaringan, disk, baterai (grafik kecil). **[Dev]** alert bila satu proses > 150% CPU selama 60 detik, dengan tombol Hentikan | Should |
| FR-27 | **Layar tanpa notch / monitor eksternal:** bentuk pill di tengah atas; pilih layar (built-in, utama, semua) | Should |
| FR-28 | Mode Presentasi otomatis saat screen share terdeteksi (hanya bila spike T2.7 berhasil) | Could |
| FR-29 | **[Dev] Touch ID untuk `sudo`:** cek apakah sudah aktif; bila belum, tampilkan perintah siap jalan untuk `/etc/pam.d/sudo_local` (§F16) | Should |

### v1.2 — Notifikasi & Integrasi

| ID | Requirement | Prioritas |
|---|---|---|
| FR-68 | **Notifikasi di notch:** notifikasi app (WhatsApp, Telegram, Slack, Mail, dll.) tampil sebagai P1 di notch: ikon app, judul, cuplikan; klik → buka app. Daftar app yang diizinkan; isi disembunyikan di Mode Presentasi (spike T3.5, §F18) | Should |
| FR-69 | **Balas pesan:** iMessage lewat app Pesan; WhatsApp/Telegram bila banner-nya punya aksi Reply (spike T3.5); lainnya [Buka chat] | Could |
| FR-82 | **Panggilan masuk:** FaceTime/iPhone (Continuity) sebagai P0 dengan Terima/Tolak | Could |
| FR-83 | **Kontrol meeting:** mute, kamera, share untuk Zoom/Teams/Meet dari Peek | Could |
| FR-75 | **Reminder:** reminder yang jatuh tempo hari ini (EventKit) di Home; centang selesai dari notch; P1 saat jatuh tempo | Should |
| FR-85 | **Tambah cepat:** ketik "Rapat tim besok 10.00" atau "Beli kopi jam 3" → event/reminder baru (tanggal dikenali `NSDataDetector`) | Could |
| FR-45 | **Cuaca:** suhu + ikon di Home dan Peek, prakiraan per jam di Expanded (Open-Meteo, tanpa API key); lokasi dari kota yang diisi manual atau Location Services (opt-in) | Should |
| FR-76 | **Progres download:** download Safari/Chrome/Firefox di `~/Downloads` tampil sebagai P2 (nama, ukuran, persentase bila tersedia); selesai → P1 + "Tampilkan di Finder" / "Kirim ke Shelf" | Could |
| FR-30 | **[Dev] GitHub:** run GitHub Actions di branch yang sedang kamu kerjakan (berjalan → aktivitas, gagal → P1), dan jumlah PR yang menunggu review-mu. Memakai login `gh` yang sudah ada | Must |
| FR-31 | **[Dev] Script widget:** script di `~/.config/dylan/widgets/` dijalankan berkala; output JSON-nya jadi tile di tab Dev atau aktivitas (§F11) | Should |
| FR-32 | **[Dev] Codex CLI:** giliran agent selesai → aktivitas; status berjalan bila datanya tersedia | Should |
| FR-33 | **[Dev] Docker:** container berjalan/berhenti, restart/stop, buka log di terminal | Could |
| FR-34 | **[Dev]** Agent lain (Cursor CLI, OpenCode) lewat adapter yang sama | Could |

### v1.3 — Ekstra

| ID | Requirement | Prioritas |
|---|---|---|
| FR-63 | Visualizer audio nyata: equalizer mengikuti audio app media lewat Core Audio process tap (macOS 14.2+, izin audio capture, tanpa Screen Recording). Tanpa izin → tetap animasi dekoratif | Could |
| FR-64 | Spotify Web API (opt-in, login OAuth PKCE): like/simpan lagu, daftar playlist untuk putar cepat, antrean berikutnya | Could |
| FR-43 | Transform file di shelf: konversi/resize gambar, kompres video, gabung PDF, semuanya lokal | Could |
| FR-77 | Hapus background gambar di shelf, lokal dengan Vision (macOS 14+); hasil PNG transparan masuk shelf | Could |
| FR-86 | Floating basket: goyang kursor saat men-drag file → keranjang kecil muncul di dekat kursor (berguna di monitor eksternal yang jauh dari notch) | Could |
| FR-87 | Salin teks dari gambar (OCR, Vision `VNRecognizeTextRequest`) untuk item gambar di clipboard dan shelf | Could |
| FR-88 | **Screenshot:** capture area, jendela, atau layar penuh dari menu bar (D38) atau notch yang melebar jadi pemilih mode (D39); shortcut ⌥⇧1/2/3 (tidak bentrok dengan ⇧⌘3/4/5 macOS), timer 3/5/10 detik, loupe koordinat + warna piksel, notch dan ikon desktop tidak ikut terekam | Should |
| FR-89 | Hasil capture di notch sebagai P2 (D40): thumbnail bisa diseret ke app lain atau Shelf, langsung disalin; tombol Percantik, Simpan, Pin (jendela melayang), Teks. Riwayat lokal (default 30 hari) dan ⌥⇧E membuka capture terakhir | Should |
| FR-90 | Capture teks (OCR) ⌥⇧T: teks area langsung disalin (Vision, Indonesia & English, di Mac); QR code yang terbaca ditawarkan sebagai link | Should |
| FR-91 | Scrolling capture ⌥⇧4 (D42): pilih area lalu scroll; potongan disambung, header lengket dibuang, batas 20.000 px, Esc menyimpan yang sudah terambil | Could |
| FR-92 | Editor anotasi (D41): panah, kotak, teks, sorot, blur/piksel, nomor urut, crop, ambil warna; undo/redo; Salin ⌘C langsung; blur otomatis data sensitif opsional (detektor rahasia Clipboard, default mati supaya Salin tidak menunggu OCR); ekspor PNG @2x / JPG / WebP | Could |
| FR-93 | Studio percantik (D44): bingkai (macOS, browser, kaca), sudut, bayangan, rasio + preset sosial (X, Instagram, LinkedIn), latar gradien/mesh + grain, tata letak 3D, jumlah salinan, ukuran; Salin hasil siap tempel | Could |
| FR-94 | Rekam layar dari menu Screenshot (D38: "Segera") | Won't (v1.x) |
| FR-95 | **Suhu & Kipas:** tab Suhu di notch (D45) dengan suhu CPU, GPU, SSD, baterai (IOHID, tanpa root), RPM tiap kipas dan grafik CPU; hanya muncul di Mac yang punya kipas dan bisa disembunyikan | Should |
| FR-96 | Preset kipas Otomatis (default, dikendalikan macOS), Senyap, Seimbang, Performa, Maksimal, dan Kurva, dari notch, menu bar Fan ▸ (D46), dan shortcut ⌃⌥⇧0–4; titik kecil di ikon menu bar saat bukan Otomatis | Should |
| FR-97 | Status kipas di notch (D47): Compact P3 saat mode manual; Peek P1 "terlalu panas" saat ≥ 95 °C selama 30 dtk, menyebut proses terberat dan tombol Kipas maks (muncul lagi paling cepat 15 menit); Compact P2 "Kembali ke Otomatis"; status manual dan "Kembali ke Otomatis" bisa disembunyikan dari notch (Settings) | Should |
| FR-98 | Settings Suhu & Kipas (D48): mode per kipas (Otomatis, RPM tetap, Kurva), kurva 4 titik pada sensor pilihan dengan respons Cepat/Halus (rata-rata 10 dtk), kembali otomatis saat suhu turun (< 65 °C selama 5 menit), ambang peringatan, suhu di menu bar, °C/°F | Should |
| FR-99 | Helper kipas (D49): daemon `SMAppService` yang menulis `F<n>Md`/`F<n>Tg` ke SMC, dipasang sekali dengan password admin; hanya menerima Dylan yang ditandatangani tim yang sama; tidak pernah di bawah RPM minimum pabrik; kembali ke Otomatis bila Dylan keluar, crash, sleep, atau diam 10 dtk; tidak menyentuh kipas yang diatur app lain | Should |
| FR-100 | **Optimasi penyimpanan:** pindai folder rumah (hanya baca) dan tampilkan daftar bercentang per kategori; tiap item punya judul, ukuran, lokasi (bisa dibuka di Finder), dan dampak bila dihapus (Rendah/Sedang/Tinggi + penjelasan) | Should |
| FR-101 | Kategori: cache app, log, Trash, file besar & lama di Downloads, file besar milik user, cadangan iPhone, capture Dylan; [Dev] Xcode DerivedData/Archives/DeviceSupport, cache simulator, cache npm/Gradle, `node_modules` lama | Should |
| FR-102 | Bersihkan dengan konfirmasi: yang bisa dibuat ulang (cache, log, build) dihapus permanen; file milik user dipindah ke Trash; default hanya item berdampak rendah yang dicentang; cache app yang sedang berjalan tidak dicentang | Should |
| FR-103 | Peringatan di notch saat ruang kosong tinggal sedikit (default < 10 GB atau < 10 %), dicek tiap 30 menit, dengan tombol Bersihkan | Should |
| FR-104 | Settings dikelompokkan per kegunaan di sidebar (Notch, Sistem, Alat, Developer) | Should |
| FR-46 | Scratchpad: catatan cepat dalam satu hover | Could |
| FR-79 | Kamera cermin: preview kamera depan di Expanded untuk cek penampilan sebelum meeting; kamera hanya aktif selama panel terbuka | Could |
| FR-81 | "Waktunya berangkat": untuk event dengan lokasi fisik, hitung waktu tempuh (MapKit) dan beri P1 saat harus berangkat | Could |
| FR-80 | **Widget lock screen (eksperimental):** jam, Now Playing, baterai, cuaca di lock screen. Butuh API privat SkyLight, jadi wajib spike T4.1, mati secara default, dan otomatis nonaktif bila macOS menolak | Could |
| FR-41 | **[Dev]** Terminal cepat di notch (drop-down ala Quake, pakai SwiftTerm), bisa diserahkan ke Terminal/VS Code | Could |
| FR-42 | **[Dev]** MCP server lokal: Claude Code bisa memanggil `notify`, `activity`, `shelf_add` | Could |

### v2.0 — Face Unlock (eksperimental, hanya bila spike T5.0 = Go)

| ID | Requirement | Prioritas |
|---|---|---|
| FR-50 | **Pendaftaran wajah:** opt-in dengan peringatan keamanan yang jelas; ambil ±20 frame dari beberapa sudut; simpan **embedding saja** (tanpa foto) secara terenkripsi; bisa dihapus kapan saja | Must |
| FR-51 | **Buka kunci:** saat layar terkunci lalu menyala lagi (buka lid, tekan tombol, gerakkan mouse), kamera aktif maksimal 8 detik. Bila wajah cocok dan lolos cek liveness, Dylan mengisi password login ke lock screen | Must |
| FR-52 | **Syarat keamanan** (semua wajib lolos): terkunci < 60 menit (bisa diatur); tepat satu wajah di kamera; maksimal **1** kali isi password per sesi kunci; gagal sekali → fitur nonaktif sampai kamu membuka kunci secara manual; opsional hanya di Wi-Fi tepercaya | Must |
| FR-53 | **Liveness dasar:** wajib ada kedipan atau gerak kepala kecil dalam jendela 8 detik. Ini menolak foto, tapi **tidak** menolak video (§F15) | Must |
| FR-54 | **Transparansi:** setelah terbuka, notch menampilkan "Dibuka dengan wajah" (P1); riwayat 50 kejadian terakhir (waktu, hasil, skor; tanpa foto) | Must |
| FR-55 | Tombol "Matikan Face Unlock" di menu bar + otomatis mati saat Mode Presentasi aktif | Should |

## 1.8 Requirement Non-Fungsional

| Aspek | Target |
|---|---|
| CPU idle (Closed, tanpa aktivitas) | < 1% rata-rata. Utamakan event (distributed notification, IOKit, CoreAudio listener, socket Discord). Polling hanya untuk fitur yang membutuhkannya (clipboard 0,5 s, port 10 s, GitHub 60 s, cuaca 30 menit) |
| CPU saat Expanded/animasi | < 10% di M1 Pro |
| Memori | < 150 MB |
| Animasi | 120 fps di ProMotion; spring (response 0,35 s, damping 0,8); hormati *Reduce Motion* |
| Latensi | Hover → Peek < 100 ms setelah delay; event hook → tampil < 300 ms |
| Hook Claude Code | `dylan hook` selesai < 50 ms untuk event biasa. **Fail-open:** bila Dylan mati atau hang, hook langsung keluar tanpa output dan tidak pernah mengganggu Claude Code |
| Stabilitas | Bertahan saat sleep/wake, ganti layar, ganti Space, dan restart Dylan. Crash Dylan tidak memengaruhi terminal/agent |
| Privasi | Tanpa telemetry/analytics. Tanpa jaringan kecuali yang opt-in: GitHub, cuaca (nama kota dikirim ke geocoding Open-Meteo sekali, lalu koordinat dibulatkan 2 desimal), lirik (LRCLIB, judul + artis), waktu tempuh Apple Maps untuk "Waktunya berangkat" (lokasi kamu + tujuan event), Spotify Web API (akun opsional, PKCE dengan Client ID milik user; refresh token di Keychain)/oEmbed, tukar token OAuth Discord ke `discord.com`. Data Discord sendiri lewat socket lokal ke app Discord; Dylan tidak punya server |
| Keamanan | Socket hanya bisa diakses user sendiri (0600). Dylan tidak menjalankan perintah yang datang lewat socket. Edit file config selalu dengan backup |
| Aksesibilitas | Label VoiceOver di semua kontrol; navigasi keyboard di Expanded; kontras teks ≥ 4,5:1 |
| Kompatibilitas | macOS 15+, diuji di macOS 27, Apple Silicon (Intel tidak ditargetkan) |
| Bahasa | UI Bahasa Indonesia dan English (FR-18), lengkap di v1.0. Semua string di `Localizable.strings` per bahasa (`id.lproj`, `en.lproj`; String Catalog butuh `xcstringstool` yang hanya ada di Xcode); tidak ada teks UI yang di-hard-code, dan unit test memastikan kedua bahasa punya key dan argumen yang sama. Format tanggal, jam, durasi, dan angka mengikuti bahasa terpilih. Bahasa lain bisa ditambah tanpa mengubah kode |
| Face Unlock (v2.0) | Layar menyala → terbuka ≤ 2 s; kamera hanya aktif ≤ 8 s per percobaan (lampu hijau kamera menyala selama itu); 0 dari 20 percobaan pakai foto wajahmu berhasil membuka; embedding tidak pernah keluar dari Mac |

## 1.9 Metrik Sukses (pemakaian pribadi, 2 minggu)

- Dipakai setiap hari kerja tanpa pernah dimatikan karena mengganggu.
- Selama 2 minggu, jendela Spotify dan Discord hampir tidak pernah dibuka hanya untuk ganti lagu, mute, atau cek siapa yang bicara.
- Profil Umum: pengguna non-engineer (minimal 2 orang) bisa menyelesaikan onboarding tanpa bantuan dan tanpa melihat satu pun istilah developer.
- (Mode Developer) ≥ 90% permission prompt Claude Code dijawab < 1 menit. Bandingkan dengan sebelum memakai Dylan lewat timestamp di transcript.
- Tidak ada meeting yang telat > 2 menit karena lupa.
- Tidak ada token/password yang tersimpan di riwayat clipboard di disk (dicek manual, §5).
- CPU idle < 1% di Activity Monitor selama 1 jam.

## 1.10 Asumsi, Risiko & Mitigasi

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Format hook Claude Code berubah | Status agent salah/kosong | Parser toleran (field tak dikenal diabaikan); fixture payload asli untuk unit test; `dylan doctor` memeriksa versi `claude` dan hook terpasang |
| Hook `PermissionRequest` yang menunggu jawaban menahan prompt di terminal | User yang sedang di terminal harus menunggu | Hook bertanya ke Dylan dulu. Bila terminal sesi sedang di depan, fitur mati, atau Mode Presentasi aktif, hook langsung lepas tanpa keputusan sehingga prompt normal muncul. Timeout 30 s. Tombol "Buka terminal" melepas seketika |
| Merusak `~/.claude/settings.json` milik user, yang sudah berisi banyak hook | Claude Code error | Merge JSON, backup bertanggal, tampilkan diff, validasi sebelum tulis, tulis atomik, tombol "Lepas hook", unit test merge |
| Akses MediaRemote (API privat) dibatasi sejak macOS 15.4 | Now Playing untuk browser/app lain tidak jalan | Spotify & Music lewat AppleScript + distributed notification (cukup untuk persona). Browser lewat pendekatan `mediaremote-adapter` hanya bonus (spike T0.3), bisa rusak di update macOS |
| Compact menutupi item menu bar di samping notch | Menu/ikon status tidak bisa diklik selama ada aktivitas | Closed persis seukuran notch. Telinga Compact ≤ 100 pt per sisi. Opsi "indikator titik saja" untuk P2/P3. Area di luar bentuk notch tembus klik |
| Isi notch terlihat saat screen share | Data sensitif bocor | Mode Presentasi (manual + hotkey). Coba juga `sharingType = .none`, tapi belum pasti dihormati ScreenCaptureKit, jadi wajib diverifikasi |
| Polling (clipboard, lsof, GitHub) boros baterai | Baterai cepat habis | Interval adaptif; berhenti saat layar mati/sleep; GitHub pakai ETag; lsof hanya bila fitur aktif |
| Rate limit GitHub | Status CI terlambat | 60 s saat idle, 15 s saat ada run berjalan, ETag (respons 304 tidak memakan kuota) |
| Clipboard menyimpan rahasia | Kebocoran | §2.8: tipe concealed, app diabaikan, pola token, file 0600, "Hapus semua" |
| Update macOS mengubah perilaku jendela di atas menu bar | Notch tidak tampil | Level jendela bisa diatur; checklist uji tiap update macOS |
| **Face Unlock bisa dibobol** dengan video/foto wajahmu atau orang yang mirip | Mac terbuka oleh orang lain; data pasien terbuka | Opt-in + peringatan; liveness; syarat FR-52; riwayat; rekomendasi tetap memakai Touch ID untuk tempat umum. Jangan aktifkan bila Mac dipakai untuk data sensitif di tempat umum |
| Password login harus disimpan Dylan agar bisa diisi ke lock screen | Bila Keychain/app disusupi, password bocor | Disimpan di Keychain dengan akses hanya untuk Dylan; tidak pernah ditampilkan/di-log; hapus otomatis saat fitur dimatikan |
| macOS memblokir akses kamera atau input keyboard sintetis saat layar terkunci | Fitur tidak mungkin dibuat | Spike T5.0 dengan keputusan Go/No-go sebelum ada kode produksi |
| Password diganti tapi yang tersimpan versi lama | Percobaan gagal menambah hitungan gagal login | Maksimal 1 percobaan; gagal → fitur nonaktif dan minta password baru |
| Signature ad-hoc berubah tiap build | Keychain meminta izin ulang untuk item password | Dicatat di README; untuk pemakaian harian pakai build yang sama |
| RPC Discord untuk app yang belum di-approve: hanya tester terdaftar (maks 50), 10 server & 10 channel, satu app pengontrol voice | FR-65/66 tidak jalan untuk user umum dengan Client ID bersama; app lain (mis. Streamdeck) bisa berebut kontrol voice | Tiap user membuat app Discord sendiri (panduan langkah demi langkah) sehingga otomatis tester; cadangan FR-67 tanpa RPC; pesan jelas bila kontrol voice dipegang app lain. Spike T0.5 menentukan |
| Mirror notifikasi tidak punya API resmi | FR-68 rusak di update macOS | Spike T3.5 membandingkan cara yang ada (Accessibility pada banner Notification Center vs. database notifikasi yang butuh Full Disk Access); pilih yang paling sedikit izin; fitur mati otomatis bila gagal |
| Widget lock screen memakai API privat SkyLight | Bisa rusak atau ditolak di macOS baru | Eksperimental, mati secara default, spike T4.1, dicek tiap update macOS |
| Baterai AirPods tidak tersedia lewat API publik untuk semua perangkat | FR-44 hanya menampilkan nama | Spike T0.6; tampilkan baterai hanya bila datanya ada |
| Kuota/aturan Spotify Web API berubah | FR-64 tidak bisa login | Opt-in, kontrol utama tetap lewat AppleScript yang tidak butuh login |
| Terlalu banyak fitur membuat Dylan terasa ramai | Pengguna umum bingung | Profil Umum dengan default sedikit; tiap fitur bisa dimatikan; fitur [Dev] tersembunyi |

## 1.11 Pertanyaan Terbuka

1. **Nama:** "Dylan" (*DY*namic is*LAN*d), atau ada usulan lain?
2. **Lisensi:** MIT seperti Cermin, atau GPL-3.0? MIT berarti tidak boleh menyalin kode Atoll/boring.notch (GPL). **Rekomendasi: MIT**, tulis dari nol, hanya pakai library MIT/BSD.
3. **Kalender:** apakah kalender kantor (Google Workspace) sudah tersambung ke app Kalender macOS? Kalau belum, FR-12 butuh itu dulu.
4. **Jawab izin dari notch (FR-9):** aktif secara default atau opt-in? **Rekomendasi:** opt-in, lalu putuskan default setelah spike T0.4.
5. **Terminal utama:** terminal terintegrasi VS Code, Zed, atau Terminal.app? Ini menentukan cara "fokus ke sesi".
6. **Repo GitHub yang dipantau:** cukup otomatis dari folder project yang dipakai Claude Code/terminal, atau perlu daftar manual juga?
7. **Cuaca & lock screen:** cuaca masuk v1.2; widget lock screen masuk v1.3 sebagai eksperimen (API privat). Setuju?
8. **Face Unlock:** apakah kamu menerima risikonya (bisa dibobol video wajahmu, password disimpan di Keychain)? Rekomendasi: kerjakan spike T5.0 dulu, lalu putuskan. Untuk tempat umum tetap pakai Touch ID.
9. **Model pengenal wajah:** Vision (bawaan Apple) hanya mendeteksi wajah, tidak mengenali *siapa*. Butuh model embedding wajah Core ML. Banyak model populer berlisensi non-komersial; kalau Dylan dibuka sebagai open-source MIT, pilih model yang lisensinya cocok.
10. **Discord:** yang paling penting voice (mute/deafen, siapa bicara) atau DM/mention? Keduanya ada di v1.1; urutannya menentukan mana yang dikerjakan dulu bila spike T0.5 hanya berhasil sebagian.
11. **Pesan:** app chat apa yang paling sering dipakai (WhatsApp, Telegram, Slack, iMessage)? Ini menentukan app default yang diizinkan di FR-68.
12. **Profil default:** saat dibuka pertama kali, tanya "Umum atau Developer?" di onboarding (rekomendasi), atau langsung Umum?

## 1.12 Referensi Kompetitor

Dicek 3 November 2026 dari situs, docs, README, dan release notes resmi. Alcove dan DynamicLake hanya sedikit mempublikasikan detail; klaim yang tidak bisa diverifikasi dari sumber resmi ditandai *(belum terverifikasi)*.

| | **Droppy** | **Atoll** | **DynamicLake** | **Alcove** |
|---|---|---|---|---|
| Harga & lisensi | $9,99 sekali bayar, trial 3 hari; closed-source | Gratis, open-source GPL-3.0 | Berbayar (Pro), ±$14–17 *(belum terverifikasi)*; closed-source, plugin wajib open-source | $12,99 sekali bayar, trial 72 jam; closed-source |
| Kekuatan | Paling lengkap (±40 "droplet"): shelf + floating basket + konversi, clipboard + OCR, Spotify/Apple Music + lirik, notifikasi + **balas iMessage/WhatsApp/Telegram**, kontrol meeting, lock screen, HUD, baterai perangkat Bluetooth, **coding agents**, terminal, hapus background, kamera cermin, stay awake | Media terluas (Spotify, Music, TIDAL, Cider, YouTube Music via `mediaremote-adapter`), **lirik LRCLIB**, visualizer, AirPlay picker, volume per app, HUD lengkap, indikator privasi, Focus, download, lock screen widgets, stats lengkap, color picker, keep awake, terminal, SDK extension | Notifikasi pesan (iMessage, WhatsApp, Telegram, Slack, email), **DynaCall** (terima/tolak panggilan), antrean Apple Music + waveform, DynaDrop/DynaClip (konversi, AirDrop, share link), reminder, cuaca, **plugin market**, miniLake/pill, widget lock screen Liquid Glass | **Polish terbaik:** transisi halus, Live Activities, gestur swipe, HUD yang bisa diatur, notifikasi instan, lock screen widgets |
| Kelemahan | Berbayar; sangat banyak fitur sehingga terasa ramai | GPL (kodenya tidak boleh disalin ke Dylan yang MIT); banyak izin; port RPC sempat terbuka ke seluruh jaringan lokal (diperbaiki di 2.3.3) | Berbayar; detail teknis jarang dipublikasikan | Berbayar; fitur paling sedikit (tanpa shelf/clipboard/timer *(belum terverifikasi)*); bergantung pada API privat (diakui di FAQ-nya) |
| Discord | Notifikasi + tombol buka chat (tanpa voice) | Tidak ada | Tidak ada | Tidak ada |

### Yang diadopsi Dylan (terbaik dari masing-masing)

| Fitur | Diambil dari | Versi Dylan |
|---|---|---|
| Kontrol Spotify & Apple Music lengkap (shuffle, repeat, love, volume) | Droppy, Atoll, DynamicLake | FR-60: + **putar cepat** playlist yang di-pin, aksen warna artwork |
| Media browser & app lain | Atoll (`mediaremote-adapter`) | FR-11: bila spike T0.3 berhasil di macOS 27 |
| Lirik tersinkron | Atoll (LRCLIB), Droppy | FR-62: LRCLIB, opt-in, cache lokal |
| Visualizer, waveform | Atoll, DynamicLake, Alcove *(belum terverifikasi)* | FR-63: Core Audio process tap, tanpa Screen Recording |
| AirPlay/output picker, volume per app | Atoll, Droppy | FR-61, FR-84 |
| Like lagu Spotify (Web API) | Atoll (OAuth PKCE), Droppy (Client ID sendiri) | FR-64, opt-in |
| HUD volume/brightness/backlight | Keempatnya | FR-40, spike T2.9 |
| Baterai & charging, AirPods/Bluetooth | Keempatnya; baterai perangkat: Droppy, Atoll | FR-70, FR-44 |
| Indikator kamera/mic, Focus, download | Atoll | FR-71, FR-72, FR-76 |
| Notifikasi di notch + balas pesan | Droppy, DynamicLake | FR-68, FR-69: daftar izin per app, isi tidak disimpan, tersembunyi di Mode Presentasi |
| Panggilan masuk | DynamicLake (DynaCall) | FR-82 |
| Kontrol meeting (mute/kamera/share) | Droppy | FR-83 |
| Countdown meeting + Join | Droppy, DynamicLake | FR-12, + P0 saat 1 menit sebelum |
| Kalender, reminder, tambah cepat | Droppy, DynamicLake | FR-75, FR-85 |
| Cuaca | Atoll (Open-Meteo), DynamicLake, Droppy | FR-45: Open-Meteo, tanpa API key |
| Widget lock screen | Keempatnya | FR-80: eksperimental, mati secara default |
| Shelf, AirDrop, konversi, floating basket, hapus background, OCR | Droppy, DynamicLake, Atoll | FR-23, FR-43, FR-77, FR-86, FR-87; + aksi dev di Mode Developer |
| Clipboard history | Droppy, Atoll | + proteksi rahasia; smart detect JWT/JSON/timestamp di Mode Developer |
| Color picker, keep awake | Atoll, Droppy | FR-73, FR-74 |
| Kamera cermin | Droppy | FR-79 |
| Timer & Pomodoro | Droppy, Atoll | FR-13 |
| Stats sistem | Atoll, Droppy | FR-26, + alert proses boros CPU [Dev] |
| Pantau coding agent + jawab izin | Droppy (Agents) | [Dev] Multi-sesi, `+x −y` dari git, fokus ke jendela yang tepat, fail-open, tidak menahan prompt terminal |
| Terminal di notch, Xcode builds | Droppy, Atoll | [Dev] Digeneralisasi jadi **command tracker** + Live Activity API untuk script apa pun |
| Gestur swipe, hover | Atoll, Alcove | Sama |
| Polish animasi, Duo, pill tanpa notch | Alcove, DynamicLake | Sama, dan dijadikan acuan kualitas desain |
| Plugin/extension | DynamicLake (market), Atoll (SDK) | Versi sederhana: **CLI + script widget**, tanpa SDK/marketplace; socket lokal 0600, tidak pernah port jaringan |
| miniLake / mode minimal | DynamicLake, Atoll | Pengaturan "Compact saja": Expanded hanya lewat klik/hotkey |
| Tema (glass/hitam, aksen) | Droppy, DynamicLake | FR-78 |

**Baru di Dylan (tidak ada di keempat referensi):** Discord voice + DM/mention (FR-65–67), profil Umum/Developer (FR-17), Mode Presentasi (FR-16), Face Unlock (v2.0), dan Touch ID untuk `sudo` (FR-29).

### Yang sengaja tidak diambil
- **Di luar fungsi notch / sudah ada app khusus:** kontrol Apple TV, window snapping, uninstaller, emoji picker (macOS sudah punya ⌃⌘Space), app switcher (DynaSwitcher), launcher, teleprompter, efek kursor (LiquidMouse), suara keyboard mekanik (Mechey).
- **Butuh cloud/server:** AI rewrite, AI screen assistant (Gemini), Droppy Cloud share link, sinkronisasi app iPhone. Bertentangan dengan prinsip lokal & tanpa akun.
- **Pelacakan kuota AI** (Atoll, Droppy): sudah ditangani CodexBar.
- **Mode listening AirPods (ANC/Transparency)**: butuh API privat Bluetooth; dipertimbangkan lagi setelah v1.3.

---

# BAGIAN 2 — SPEC FITUR & TEKNIS

## 2.1 Arsitektur

```
 Claude Code hooks ─┐
 zsh preexec/precmd ┼─► dylan (CLI) ──unix socket──► Bridge ──┐
 script user ───────┘                                          ▼
 Discord app ──discord-ipc──► DiscordRPC ──┐
                                           ▼
                         Providers ──────────────────► ActivityCenter ──► NotchPanel (NSPanel + SwiftUI)
                         Umum: Media · Lyrics ·         (prioritas,        ├─ Closed / Compact (telinga)
                         Calendar · Reminders · Timer   antrean, Duo,      ├─ Peek (hover)
                         Battery · Bluetooth · HUD ·    riwayat)           └─ Expanded (tab)
                         Privacy · Focus · Notifications ·    ▲
                         Shelf · Clipboard · ColorPicker ·    │
                         KeepAwake · Weather · Downloads ·    │
                         Stats                                │
                         [Dev]: Agents · Commands · Ports ·   │
                         GitHub · Scripts · Docker            │
                                       PresentationMode ───────┘ (memfilter isi sensitif)
                                       Profile (Umum/Developer) ─► menyalakan/mematikan provider [Dev]
```

- **ActivityCenter** (logika murni di `DylanCore`, dengan unit test): menerima `Activity` dari semua sumber, lalu menentukan apa yang tampil di slot Compact, kapan Peek muncul otomatis, dan apa yang masuk riwayat.
- **Bridge:** server unix socket di dalam app. Semua sumber eksternal (hook, shell, script) lewat CLI `dylan`, jadi hanya ada satu protokol.
- **Providers:** satu file per fitur; masing-masing hanya aktif bila fiturnya dinyalakan. Provider [Dev] tidak pernah dijalankan, dan izinnya tidak pernah diminta, selama profil Umum aktif.
- **DiscordRPC:** client IPC lokal ke app Discord (bukan lewat Bridge, karena arahnya Dylan → Discord).

## 2.2 Tech Stack

| Komponen | Pilihan | Alasan |
|---|---|---|
| Bahasa/UI | Swift 6, SwiftUI + AppKit (`NSPanel`) | Native, animasi 120 Hz |
| Build | SwiftPM + `scripts/build.sh` (membundel `.app`, ad-hoc sign) | Mac pengembang hanya punya Command Line Tools (sama seperti Cermin) |
| Target | macOS 15+; efek glass bila macOS 26+ | |
| Dependensi v1.0 | **Tidak ada** dependensi pihak ketiga, kecuali `mediaremote-adapter` untuk media browser bila spike T0.3 = Go dan lisensinya cocok dengan MIT | |
| Kalender | EventKit | Resmi |
| Media | AppleScript (Spotify, Music) + `DistributedNotificationCenter`; MediaRemote opsional (browser/app lain) | Resmi & stabil |
| Lirik | LRCLIB (`lrclib.net/api/get`, format LRC), cache di disk | Gratis, tanpa API key |
| Output audio | Core Audio (`kAudioHardwarePropertyDefaultOutputDevice`) | Publik |
| Visualizer (v1.3) | Core Audio process tap (`AudioHardwareCreateProcessTap`, macOS 14.2+) | Tanpa Screen Recording |
| Discord | Discord RPC lewat unix socket lokal `$TMPDIR/discord-ipc-{0..9}` (frame: opcode + panjang + JSON); OAuth `authorize` dengan Client ID milik user | Tanpa library, tanpa server |
| Baterai & charging | IOKit Power Sources (`IOPSNotificationCreateRunLoopSource`) | Event, bukan polling |
| Bluetooth/AirPods | IOBluetooth (notifikasi connect/disconnect); baterai dari properti perangkat bila ada (spike T0.6) | |
| Kamera/mikrofon dipakai | CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere`, Core Audio `kAudioDevicePropertyDeviceIsRunningSomewhere` | Publik, tanpa izin kamera/mic |
| HUD | Event tombol media/brightness (spike T2.9) + IOKit/Core Audio untuk nilai | |
| Keep awake | `IOPMAssertionCreateWithName` | Publik |
| Color picker | `NSColorSampler` | Publik, tanpa Screen Recording |
| Reminder | EventKit | Resmi |
| Cuaca | Open-Meteo + CoreLocation (opt-in) atau kota manual | Tanpa API key |
| Hapus background (v1.3) | Vision `VNGenerateForegroundInstanceMaskRequest` | Lokal |
| Notifikasi (v1.2) | Ditentukan spike T3.5 | Belum ada API resmi |
| Clipboard | Polling `NSPasteboard.changeCount` tiap 0,5 s | Tidak ada API notifikasi |
| Penyimpanan | JSON + SQLite (`libsqlite3` bawaan sistem) di `~/Library/Application Support/Dylan/` | Tanpa dependensi |
| Stats | `host_processor_info`, `host_statistics64`, IOKit (baterai), `getifaddrs` | Pendekatan yang sama dengan Stats/Atoll |
| Port | `/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN` + `proc_pidinfo` (cwd proses) | |
| GitHub | `gh api` (memakai login `gh` yang sudah ada); cadangan: token di Keychain | Tanpa OAuth sendiri |
| Hotkey global | Carbon `RegisterEventHotKey` | Tanpa izin Accessibility |
| Terminal (v1.3) | SwiftTerm (MIT) | |
| Test | Swift Testing | |

## 2.3 Struktur Folder

```
dylan-mac/
├── PRD.md
├── Package.swift
├── Resources/                 # Info.plist, Dylan.entitlements
├── scripts/                   # build.sh, make-icon.swift
├── design/                    # hasil Claude Design
├── docs/                      # hasil spike
├── examples/widgets/          # contoh script widget (v1.2)
├── Sources/
│   ├── DylanCore/             # logika murni + unit test
│   │   ├── ActivityCenter.swift   # prioritas, antrean, Duo, riwayat
│   │   ├── NotchGeometry.swift    # ukuran/posisi dari safe area layar
│   │   ├── BridgeProtocol.swift   # pesan socket (Codable)
│   │   ├── ClaudeHookEvent.swift  # payload hook → status sesi
│   │   ├── SettingsMerge.swift    # pasang/lepas hook di ~/.claude/settings.json
│   │   ├── Detectors.swift        # JWT, JSON, timestamp, Base64, token rahasia…
│   │   ├── CommandFilter.swift    # threshold & daftar abaikan
│   │   ├── MeetingLink.swift      # link Zoom/Meet/Teams dari event
│   │   ├── FaceUnlockPolicy.swift # syarat FR-52, liveness, ambang skor (v2.0)
│   │   ├── DiscordFrame.swift     # encode/decode frame IPC Discord + event voice
│   │   ├── LRCParser.swift        # lirik LRC → baris bertimestamp
│   │   ├── DownloadWatcher.swift  # .crdownload/.download/.part → progres
│   │   ├── Profile.swift          # profil Umum/Developer → fitur aktif
│   │   └── LsofParser.swift
│   ├── Dylan/                 # app
│   │   ├── App/               # DylanApp, AppModel, Onboarding, Settings
│   │   ├── Notch/             # NotchPanel, NotchView, Compact, Peek, Expanded, gestur, drop zone
│   │   ├── Bridge/            # SocketServer
│   │   ├── Providers/         # Media, Lyrics, Discord, Notifications, Calendar, Reminders, Timer, Battery, Bluetooth, HUD, Privacy, Focus, Clipboard, Shelf, ColorPicker, KeepAwake, Weather, Downloads, Stats, LockScreen, FaceUnlock; [Dev] Agents, Commands, Ports, GitHub, Scripts, Docker
│   │   └── UI/                # tab, komponen, theme
│   └── DylanCLI/              # executable CLI, dibundel ke Dylan.app/Contents/Helpers/dylan
└── Tests/
    ├── DylanCoreTests/
    └── Fixtures/              # payload hook asli dari spike T0.4
```

## 2.4 Model Notch

### Geometri
- Lebar notch = `screen.frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width`. Tinggi notch = `safeAreaInsets.top`. Jangan di-hard-code.
- Layar tanpa notch (`safeAreaInsets.top == 0`): pill ±200 × 32 pt di tengah atas, 6 pt dari tepi (v1.1).
- Jendela: `NSPanel` non-activating, borderless, transparan, level `.mainMenu + 3`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`.
- Ukuran jendela tetap sebesar Expanded. Klik di luar bentuk notch diteruskan ke app di bawahnya (atur `ignoresMouseEvents` sesuai posisi kursor).

### State & ukuran (perkiraan; finalkan di Claude Design)

| State | Ukuran | Isi |
|---|---|---|
| Closed | = notch | Kosong (hitam menyatu) |
| Compact | notch + telinga kiri & kanan (masing-masing ≤ 100 pt) | Ikon/artwork di kiri, nilai singkat di kanan. Duo: satu aktivitas per telinga |
| Peek | lebar ±360 pt, tinggi notch + 44 pt | 1 baris detail aktivitas teratas + aksi utama |
| Expanded | ±640 × 230 pt (maks 720 × 380) | Tab bar + konten |

### Prioritas Live Activity

| Prioritas | Contoh | Perilaku |
|---|---|---|
| **P0 – urgent** | Agent butuh izin, meeting mulai ≤ 1 menit, baterai 10% | Tampil walau ada app fullscreen; Peek otomatis 4 s; tetap di Compact sampai ditangani; suara opsional |
| **P1 – hasil/pesan** | Agent selesai, command selesai/gagal, CI gagal, meeting 10 menit lagi, server baru siap, DM/mention Discord, notifikasi app, AirPods tersambung, charger dicolok, reminder jatuh tempo, download selesai | Compact 5 s (gagal: 8 s), lalu masuk riwayat |
| **P2 – berjalan** | Agent bekerja, command berjalan, timer, CI berjalan, script/deploy, voice Discord, download berjalan, keep awake | Compact selama berjalan |
| **P3 – ambient** | Now Playing, lirik, charging, cuaca, Focus | Hanya bila ada slot kosong |
| **Overlay** | HUD volume/brightness, indikator kamera/mikrofon | Tidak memakai slot Duo. HUD menimpa Compact selama 1,5 s; indikator privasi berupa titik kecil yang selalu tampil |

- Maksimal 2 slot (Duo). Slot diisi prioritas tertinggi; bila prioritasnya sama, yang terbaru menang.
- Beberapa sesi agent digabung jadi satu aktivitas di Compact ("3 agent · 1 butuh izin"); rinciannya di Peek/Expanded.
- Mode Presentasi mengganti isi aktivitas dengan teks generik, tapi status tetap terlihat.

## 2.5 Spec per Fitur

### F1 — Shell Notch (FR-1 s/d FR-5, FR-14, FR-27)
- Hover: delay 150 ms → Peek; kursor keluar area 300 ms → kembali. Klik/hotkey → Expanded. Swipe dua jari di area notch: ke bawah = buka, ke atas = tutup.
- Saat file di-drag dari mana saja dan mendekati notch, notch membuka tab Shelf sebagai drop zone (v1.1).
- Tab Expanded (urutan & on/off bisa diatur): **Home · Media · Discord · Shelf · Clipboard · Stats**, ditambah **Agents · Dev** bila Mode Developer aktif. Tab Discord hanya muncul bila Discord tersambung.
- Fullscreen: bila jendela app terdepan seukuran layar (cek via `CGWindowListCopyWindowInfo`, tanpa izin Screen Recording), panel disembunyikan kecuali P0.
- Ganti layar, ubah resolusi, atau sleep/wake → hitung ulang geometri.
- **AC:**
  - Di MBP 14", state Closed tidak bisa dibedakan dari notch.
  - Saat Closed, tidak ada item menu bar yang tertutup.
  - Hover → Peek terasa instan; Esc menutup.
  - Fokus keyboard tidak pernah dicuri saat mengetik di app lain.

### F2 — Live Activity API & CLI `dylan` (FR-6)
Protokol dan perintah ada di §2.6.
- **AC:**
  - `dylan activity start/update/end` tampil < 300 ms.
  - `dylan run -- sleep 15` menghasilkan aktivitas berjalan, lalu ✓.
  - Bila Dylan tidak jalan, CLI keluar dengan kode 0 dan menulis pesan ke stderr, sehingga script user tidak ikut gagal. Pengecualian: `dylan run` meneruskan exit code perintahnya.

### F3 — [Dev] Agents: Claude Code (FR-7, FR-8, FR-9)

**Sumber data:** hook Claude Code bertipe `command` memanggil `dylan hook claude`. CLI meneruskan JSON dari stdin, ditambah `__CFBundleIdentifier`, `TERM_PROGRAM`, dan PID parent, ke socket.

| Event hook | Yang dilakukan Dylan |
|---|---|
| `SessionStart` | Sesi baru: `session_id`, `cwd` → nama project (root git atau nama folder); app terminal dari env |
| `UserPromptSubmit` | Status "Bekerja", mulai hitung durasi |
| `PreToolUse` | Tool terkini: `Edit`/`Write`/`Read` → nama file; `Bash` → perintah (dipotong 60 karakter); lainnya → nama tool |
| `PostToolUse` | Catat file yang diubah |
| `Notification` | "Menunggu input" (P0 bila berisi permintaan izin, P1 bila sekadar idle) |
| `PermissionRequest` | Kartu izin: tool + ringkasan input; bisa dijawab dari notch (FR-9) |
| `Stop` | Selesai: durasi, `git diff --shortstat` di cwd (`+x −y`), kalimat pertama balasan terakhir dari `transcript_path` |
| `StopFailure`, `PostToolUseFailure` | Gagal / error tool |
| `SessionEnd` | Hapus sesi dari daftar |

- **Hook wajib diam.** Hook tidak boleh menulis ke stdout, kecuali keputusan `PermissionRequest`, karena stdout beberapa event (mis. `SessionStart`, `UserPromptSubmit`) bisa masuk ke konteks Claude. Selalu exit 0.
- **Jawab izin dari notch (FR-9):**
  1. `dylan hook` mengirim permintaan ke Dylan dan menunggu balasan.
  2. Dylan langsung membalas "lepas" (tanpa keputusan, sehingga prompt normal muncul di terminal) bila: fitur mati, app terminal sesi sedang di depan, layar terkunci, atau Mode Presentasi aktif.
  3. Selain itu, Dylan menampilkan P0 dengan tombol **Izinkan · Tolak · Buka terminal**. "Buka terminal" = lepas + fokus ke terminal.
  4. Tidak dijawab dalam 30 s (bisa diatur) → lepas.
  5. Output keputusan: `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`, atau `"behavior":"deny"` dengan `"message"`. Format ini wajib diverifikasi di spike T0.4.
  - Tidak ada "Izinkan selalu" di v1.0, supaya aturan izin user tidak berubah tanpa sadar.
- **Fokus ke sesi:** env → app (tabel §2.6). Untuk VS Code/Zed, jalankan `code <root>` / `zed <root>` supaya jendela project yang tepat yang muncul.
- **Pemasangan hook (FR-8)**, dari onboarding atau Settings → Agents:
  1. Baca `~/.claude/settings.json`.
  2. Tambahkan entri Dylan per event tanpa mengubah entri lain.
  3. Simpan backup `settings.json.dylan-backup-<tanggal>`.
  4. Tampilkan diff, lalu tulis secara atomik setelah disetujui.
  - Hook memakai path absolut ke CLI di dalam app. Bila app dipindah, Settings menandai hook perlu diperbarui.
  - "Lepas hook" hanya menghapus entri yang berisi `dylan hook`.
- **AC:**
  - Dua sesi paralel (VS Code + Zed) tampil terpisah dan benar.
  - Izin dijawab dari notch → Claude lanjut.
  - Saat terminal di depan, prompt terminal muncul tanpa jeda.
  - Dylan dimatikan → Claude Code tetap normal tanpa error.
  - `settings.json` yang berisi hook user lain tetap utuh setelah pasang lalu lepas.

### F4 — [Dev] Command Tracker (FR-10)
- Aktivasi: `eval "$(dylan shell-init zsh)"` di `~/.zshrc`. Bisa ditambahkan otomatis dengan persetujuan, atau disalin manual.
- `preexec` mengirim `start` (perintah, cwd, PID shell, env terminal) dan `precmd` mengirim `end` (exit code). Keduanya jalan di background (`&!`) supaya prompt tidak melambat.
- Aktivitas baru ditampilkan bila perintah masih berjalan setelah **10 s** (bisa diatur). Hasil hanya ditampilkan bila durasinya ≥ 10 s.
- Secara default, hasil hanya tampil bila terminal **tidak** sedang di depan. Bisa diubah jadi "selalu".
- Daftar abaikan default:
  - Interaktif: `vim nvim nano less more man top htop btop ssh mosh tmux screen claude codex watch`, `tail -f`.
  - Server: `npm run dev`, `pnpm dev`, `yarn dev`, `vite`, `next dev`, `rails s`, `docker compose up`. Server dipantau oleh fitur Port.
- **AC:**
  - `sleep 12 && false` → aktivitas berjalan, lalu ✗ exit 1 · 12 s.
  - Latensi prompt zsh bertambah < 5 ms.
  - `vim` tidak pernah tampil.

### F5 — Now Playing & Media (FR-11, FR-60 s/d FR-64)
- Spotify: event `com.spotify.client.PlaybackStateChanged` + AppleScript untuk artwork URL, posisi, dan kontrol (`playpause`, `next track`, `previous track`, `player position`, `sound volume`, `shuffling`, `repeating`).
- Apple Music: event `com.apple.Music.playerInfo` + AppleScript.
- Player lain (YouTube di Chrome/Safari, Podcasts, VLC): MediaRemote, bila spike T0.3 berhasil. Sejak macOS 15.4 MediaRemote tidak bisa lagi dimuat langsung oleh app pihak ketiga. Atoll memakai `mediaremote-adapter`, yang menjalankan helper lewat `/usr/bin/perl` karena proses `com.apple.*` masih punya akses; pembuatnya sendiri memperingatkan bisa rusak lagi di update macOS. Spike mencatat apakah cara ini masih jalan di macOS 27 dan apakah lisensinya cocok dengan MIT.
- Bila beberapa sumber aktif, yang terakhir diputar menang; Expanded menampilkan pemilih sumber.
- Compact: artwork kecil di kiri, equalizer di kanan. Di v1.0 equalizer hanya animasi dekoratif; visualizer nyata di v1.3 (FR-63).
- **Tab Media (Expanded):** artwork besar dengan glow warna dominan, judul, artis, album, progress bar yang bisa digeser, prev/play/next, shuffle, repeat, volume, pilih output audio (FR-61), lirik (FR-62), dan baris **Putar cepat**.
- **Putar cepat (FR-60):** user mem-pin playlist/album dengan menempelkan link Spotify (`open.spotify.com/playlist/…`) atau URI (`spotify:playlist:…`). Klik → bila Spotify belum jalan, buka di latar, lalu `play track "<uri>"`. Nama & cover diambil dari oEmbed Spotify (`open.spotify.com/oembed`, tanpa login) saat di-pin, lalu di-cache.
- Swipe horizontal di area musik → next/prev. Scroll vertikal di Compact musik → volume.
- **Lirik (FR-62):** saat lagu berganti, panggil `GET lrclib.net/api/get?track_name&artist_name&album_name&duration`. Hasil `syncedLyrics` (LRC) di-parse `LRCParser` dan disinkronkan dengan posisi pemutar; bila hanya `plainLyrics`, tampil tanpa sinkron. Cache per lagu di disk. Tidak ditemukan → bagian lirik disembunyikan.
- **Volume per app (FR-84):** Core Audio process tap per app (macOS 14.2+), slider di tab Media. Izin audio capture; tanpa izin, fitur disembunyikan.
- **Spotify Web API (FR-64, v1.3):** login OAuth PKCE dengan Client ID milik user (app Spotify Developer sendiri); token di Keychain. Untuk like lagu, daftar playlist, dan antrean.
- **AC:**
  - Ganti lagu di Spotify → notch berubah < 1 s; tidak ada polling saat musik berhenti.
  - Pin playlist, tutup Spotify, klik di notch → Spotify terbuka dan playlist mulai < 5 s.
  - Lirik bergeser tepat waktu (selisih < 0,5 s) setelah seek.
  - Video YouTube di Chrome bisa di-pause dari notch (bila spike T0.3 = Go).

### F6 — Meeting Berikutnya (FR-12)
- EventKit; ambil event hari ini dari kalender yang dipilih.
- Link meeting dicari di URL, lokasi, dan catatan event: `zoom.us/j/…`, `meet.google.com/…`, `teams.microsoft.com/l/meetup-join/…` (unit test).
- 10 menit sebelum → P1 "Standup · 10m". 1 menit sebelum → P0 dengan tombol **Join**.
- Join membuka link. Untuk Zoom, buka langsung ke app (`zoommtg://`) bila memungkinkan.
- **AC:** event dengan link Zoom → countdown tepat waktu; Join membuka Zoom.

### F7 — Timer & Pomodoro (FR-13)
- Preset 5/10/25 menit + input bebas ("45m", "1h30").
- Pomodoro 25/5; tiap siklus ke-4, istirahat 15 menit.
- Berbasis jam dinding sehingga tetap akurat setelah sleep. Selesai → P1 + suara.

### F8 — Clipboard & Dev Tools (FR-20 s/d FR-22; dev tools = [Dev])
- Riwayat 500 item / 30 hari (bisa diatur); item yang di-pin tidak kedaluwarsa. Bisa dicari.
- Shortcut ⌃⌥V membuka tab Clipboard dengan fokus di kolom cari.
- Detector (logika murni, unit test) menghasilkan kartu dengan aksi:

| Terdeteksi | Tampilan & aksi |
|---|---|
| JSON | Pretty view; salin versi pretty/minify |
| JWT | Header & payload ter-decode; `exp`/`iat` jadi waktu lokal + "kedaluwarsa 3 jam lagi". **Dianggap rahasia** (§2.8) |
| Unix timestamp (10/13 digit, tahun 2000–2100) | Waktu lokal, UTC, dan relatif |
| Base64 | Hasil decode, bila hasilnya teks UTF-8 yang terbaca |
| URL-encoded | Hasil decode |
| UUID | Salin huruf besar/kecil |
| Warna hex | Swatch warna |
| URL | Buka di browser |
| Path file | Tampilkan di Finder / kirim ke Shelf |

- Generator di tab Clipboard: UUID v4, timestamp sekarang (detik, milidetik, ISO), hash (MD5/SHA-1/SHA-256) dari teks.

### F9 — Shelf (FR-23, FR-24)
- Drop file → disimpan sebagai referensi, bukan disalin. File yang dihapus atau dipindah ditandai.
- Aksi: drag keluar (satu atau semua), Quick Look (spasi), salin path, buka di editor (`code`/`zed`), AirDrop (`NSSharingService`), zip, hapus dari shelf.
- Screenshot baru otomatis masuk shelf (Should). Lokasinya dibaca dari `defaults read com.apple.screencapture location`.
- CLI: `dylan shelf add <file…>`.

### F10 — [Dev] Dev Server & Port (FR-25)
- Tiap 10 s, hanya bila fitur aktif: jalankan `lsof -nP -iTCP -sTCP:LISTEN -F pcn`, ambil proses milik user, lalu cwd prosesnya → nama project.
- Daftar di tab Dev, contoh: `:3000  node  api-gateway  [Buka] [Salin] [Matikan]`.
- Matikan = SIGTERM, lalu tawarkan SIGKILL bila proses masih hidup setelah 3 s.
- Port baru → P1 "localhost:5173 siap · web-admin" (klik = buka di browser).
- Abaikan port milik sistem dan app umum (mis. ControlCenter di 5000/7000, Spotify, Docker internal). Daftarnya bisa diatur.

### F11 — [Dev] Integrasi (FR-30 s/d FR-33)
- **GitHub (FR-30):**
  - Repo: folder project yang muncul di sesi agent/command 7 hari terakhir (yang punya remote GitHub), ditambah daftar manual.
  - Branch: branch lokal yang sedang aktif.
  - Data lewat `gh api`: runs Actions, dan `search/issues?q=is:pr+is:open+review-requested:@me` untuk jumlah review.
  - Interval 60 s, 15 s saat ada run berjalan, pakai ETag.
- **Script widget (FR-31):**
  - File executable di `~/.config/dylan/widgets/`. Komentar header `# dylan: interval=60s` menentukan interval.
  - Output JSON:
    ```json
    {"title":"k8s prod","value":"12/12 pods","state":"ok","progress":0.4,"url":"https://…","activity":false}
    ```
    `state` bernilai `ok`, `warn`, `error`, atau `running`.
  - `activity: true` → tampil sebagai Live Activity (P2, atau P1 bila `state` = `error`).
  - Timeout 10 s; dijalankan dengan login shell user; error ditampilkan di tile.
- **Codex (FR-32):** `notify` di `~/.codex/config.toml` → `dylan hook codex`. Spike di Phase 3 menentukan data apa saja yang tersedia.
- **Docker (FR-33):** `docker ps -a --format json`. Aksi: restart, stop, dan logs (membuka terminal dengan `docker logs -f`).

### F12 — Mode Presentasi (FR-16, FR-28)
- Aktif lewat hotkey ⌃⌥⌘H, menu, atau otomatis (FR-28, bila deteksi screen share berhasil di spike).
- Saat aktif:
  - Tab Clipboard terkunci.
  - Judul aktivitas digeneralisasi ("Claude sedang bekerja", "Perintah berjalan"). Nama file, perintah, dan judul meeting disembunyikan.
  - Notifikasi, DM Discord, dan iMessage hanya tampil sebagai "Pesan baru · Discord" tanpa pengirim dan isi. Nama peserta voice Discord disembunyikan.
  - Peek otomatis mati, kecuali P0 (tanpa detail).
  - Kartu izin agent tidak muncul; permintaan langsung dilepas ke terminal.
  - Indikator kecil `eye.slash` di Compact.
- Tambahan: coba `NSWindow.sharingType = .none` supaya panel tidak ikut tertangkap screen share. Verifikasi di Zoom & Meet.
- Hotkey sengaja dibedakan dari Privacy Curtain Cermin (⌃⌥⌘P) supaya tidak bentrok.

### F13 — Stats (FR-26)
- Sampling tiap 1 s hanya saat tab Stats terbuka. Di latar, sampling tiap 10 s untuk alert.
- Grafik: CPU, GPU, memori, jaringan, disk, baterai.
- **[Dev]** Alert: satu proses > 150% CPU selama 60 s → P1 "node memakai 180% CPU · 2m", dengan tombol [Lihat] [Hentikan].
- Baterai & charging pindah ke §F19 dan berlaku untuk semua profil.

### F14 — Settings, Onboarding & Bahasa (FR-15, FR-18)
- Tab Settings:
  - **Umum:** bahasa (FR-18), profil (Umum/Developer), login item, layar, hotkey, ikon menu bar.
  - **Tampilan:** ukuran, delay hover, animasi, Duo, mode "Compact saja", tema & aksen (FR-78).
  - **Live Activity:** durasi hasil, suara, prioritas per jenis.
  - **Media:** sumber, putar cepat, lirik, output audio, Spotify Web API.
  - **Discord:** Client ID, sambungkan/putus, voice, DM/mention, keybind cadangan.
  - **Notifikasi:** app yang diizinkan, balas iMessage.
  - **Perangkat & Sistem:** baterai, Bluetooth, HUD, indikator privasi, Focus, keep awake.
  - **Utilitas:** color picker, reminder, cuaca, download, lock screen (eksperimental).
  - **Clipboard:** riwayat, app yang diabaikan, hapus semua.
  - **[Dev] Agents:** status hook, pasang/lepas, jawab izin dari notch, timeout.
  - **[Dev] Terminal:** shell integration, threshold, daftar abaikan.
  - **[Dev] Integrasi:** GitHub, script, Docker.
  - **Tentang**.
- **Bahasa (FR-18):**
  - Pilihan: Ikuti sistem (default; Indonesia bila bahasa macOS Indonesia, selain itu English), Bahasa Indonesia, English.
  - Disimpan sebagai `AppleLanguages` di defaults Dylan, sehingga sama dengan pengaturan per-app di System Settings → General → Language & Region → Applications. Mengubah salah satunya mengubah keduanya.
  - Ganti bahasa diterapkan langsung bila memungkinkan; bila sebagian teks baru berubah setelah restart, Dylan menawarkan "Buka ulang" (aktivitas yang berjalan, shelf, dan timer tetap utuh setelah dibuka ulang).
  - Format tanggal, durasi ("1 j 20 m" / "1 h 20 m"), dan waktu relatif memakai `Locale` bahasa terpilih, bukan string buatan sendiri.
  - Pesan CLI `dylan` di terminal tetap English (konvensi tool terminal dan supaya mudah dicari saat error).
  - Lirik, nama lagu, dan isi notifikasi tidak diterjemahkan.
- Onboarding, semua langkah bisa dilewati:
  1. Sambutan + **pilih bahasa** (terdeteksi otomatis dari sistem, bisa diganti di layar yang sama).
  2. **Pilih profil:** "Umum" (default) atau "Developer". Bisa diganti nanti di Settings.
  3. Pilih fitur yang ingin dinyalakan (musik, Discord, baterai & perangkat, kalender, notifikasi, …), dengan pratinjau kecil per fitur.
  4. Izin yang dibutuhkan fitur terpilih saja (Kalender, Automation Spotify/Music, Bluetooth, dll.), masing-masing dengan alasan yang jelas.
  5. **[Dev]** Pasang hook Claude Code (tampilkan diff).
  6. **[Dev]** Shell integration (tombol "Tambahkan ke ~/.zshrc", atau salin perintah) + pasang CLI ke `~/.local/bin/dylan`.

### F15 — Face Unlock (FR-50 s/d FR-55, v2.0 eksperimental)

> **Peringatan:** ini bukan Face ID. Face ID iPhone memakai kamera inframerah dan peta kedalaman 3D; Mac hanya punya kamera RGB 2D. Pengenalan wajah 2D bisa dibobol dengan video wajahmu, dan karena itu **lebih lemah dari Touch ID maupun password**. Fitur ini hanya untuk kenyamanan di tempat tepercaya (rumah/kantor).

**Kenapa harus spike dulu.** macOS tidak menyediakan API untuk biometrik pihak ketiga di lock screen. Satu-satunya jalan yang realistis adalah mengisi password login ke lock screen sebagai input keyboard sintetis. Belum pasti hal ini masih bisa di macOS 27. Authorization plugin di loginwindow sengaja tidak dipakai: butuh root, dan satu bug bisa membuatmu tidak bisa login sama sekali.

**Alur:**
1. Dylan menerima `com.apple.screenIsLocked` dan mencatat waktu kunci.
2. Layar menyala lagi (`NSWorkspace.screensDidWakeNotification`, buka lid, atau input) → bila semua syarat FR-52 terpenuhi, kamera aktif maksimal 8 s.
3. Tiap frame: Vision mendeteksi wajah (`VNDetectFaceRectanglesRequest`, `VNDetectFaceLandmarksRequest`, `VNDetectFaceCaptureQualityRequest`). Bila ada lebih dari 1 wajah → batal.
4. Wajah dipotong lalu diubah jadi embedding oleh model Core ML. Embedding dibandingkan dengan hasil pendaftaran (cosine similarity ≥ ambang ketat, dikalibrasi di spike).
5. Liveness: kedipan (jarak landmark mata) atau perubahan yaw/pitch kecil dalam jendela 8 s.
6. Semua lolos → kirim satu penekanan tombol untuk membangunkan field password, ketik password dari Keychain, Return. Butuh izin Accessibility.
7. Berhasil → P1 "Dibuka dengan wajah · 09:12" + catat riwayat. Gagal isi password → fitur nonaktif sampai unlock manual.

**Tidak akan pernah bisa (batasan macOS, juga berlaku untuk Touch ID):** login pertama setelah restart/FileVault, dan setelah logout.

**Data:**
- Embedding wajah dan password login disimpan di Keychain, hanya bisa dibaca Dylan.
- Tidak ada foto yang disimpan. Mode debug enrollment boleh menampilkan preview, tapi tidak menyimpannya.
- Matikan fitur = hapus embedding + password.

**AC (hanya bila T5.0 = Go):**
- Wajahmu, Mac terkunci < 60 menit → terbuka ≤ 2 s setelah layar menyala.
- Foto wajahmu (cetak dan di layar HP), 20 kali percobaan → 0 berhasil.
- Dua wajah di kamera → tidak terbuka.
- Password diganti → 1 percobaan gagal, fitur nonaktif, diminta password baru.
- Lampu kamera hanya menyala ≤ 8 s per percobaan.

### F16 — [Dev] Touch ID untuk `sudo` (FR-29)
- Mac persona sudah punya Touch ID (aktif untuk unlock), tapi `sudo` di terminal masih minta password. Ini alternatif biometrik yang **resmi dan aman**.
- Settings → Terminal menampilkan status: aktif bila `/etc/pam.d/sudo_local` berisi `pam_tid.so`.
- Bila belum aktif, tampilkan perintah untuk dijalankan sendiri (butuh password admin; Dylan tidak menulis ke `/etc` secara diam-diam):
  ```bash
  sed 's/^#auth/auth/' /etc/pam.d/sudo_local.template | sudo tee /etc/pam.d/sudo_local
  ```
  `sudo_local` bertahan saat update macOS.
- Bila terdeteksi `tmux`/`screen`, sarankan `pam-reattach` (Homebrew); tanpa itu Touch ID tidak muncul di dalam tmux.
- **AC:** setelah perintah dijalankan, `sudo -k && sudo true` di terminal VS Code memunculkan dialog Touch ID.

### F17 — Discord (FR-65 s/d FR-67)

**Cara utama: Discord RPC lokal.** App Discord desktop membuka unix socket `$TMPDIR/discord-ipc-0` (sampai `-9`, untuk Stable/PTB/Canary). Dylan menyambung sebagai client:
1. Frame = `opcode` (uint32 LE) + `panjang` (uint32 LE) + JSON. Opcode: 0 handshake, 1 frame, 2 close, 3 ping, 4 pong. Logika encode/decode di `DylanCore/DiscordFrame.swift` (unit test).
2. Handshake `{"v":1,"client_id":"<Client ID>"}` → event `READY`.
3. Pertama kali: `AUTHORIZE` dengan scope `rpc`, `rpc.voice.read`, `rpc.voice.write`, `rpc.notifications.read` → Discord menampilkan dialog izin → `code` ditukar menjadi token di `discord.com/api/oauth2/token` (pakai PKCE bila diterima; Client Secret hanya bila Discord mewajibkannya). Token + refresh token disimpan di Keychain. Selanjutnya cukup `AUTHENTICATE`.
4. `GET_SELECTED_VOICE_CHANNEL` + `SUBSCRIBE` ke `VOICE_CHANNEL_SELECT`, `VOICE_STATE_CREATE/UPDATE/DELETE`, `SPEAKING_START/STOP`, `VOICE_SETTINGS_UPDATE`, `NOTIFICATION_CREATE`.
5. Aksi: mute/deafen = `SET_VOICE_SETTINGS {"mute":…}` / `{"deaf":…}`; keluar = `SELECT_VOICE_CHANNEL {"channel_id":null}`.

**Client ID milik user.** Menurut dokumentasi RPC Discord, app yang belum di-approve hanya jalan untuk tester yang terdaftar (maks 50), dibatasi 10 server dan 10 channel, dan hanya satu app yang boleh mengontrol voice settings pada satu waktu. Karena itu Settings → Discord memandu user membuat app sendiri di Discord Developer Portal (± 2 menit), lalu menempelkan Client ID (dan Client Secret bila dibutuhkan; disimpan di Keychain). Pemilik app otomatis termasuk tester. Spike T0.5 memastikan alur ini jalan di Discord terbaru dan mencatat dampak batas 10 server/channel.

**Belum ada di keempat referensi.** Droppy hanya menampilkan notifikasi Discord dan tombol yang membuka chat; tidak ada yang menampilkan voice. Acuan teknis yang sudah membuktikan pendekatan RPC: NotchIsland (open-source) dan beberapa proyek notch lain yang memakai RPC lokal + OAuth.

**Tampilan:**
- Compact (P2) selama di voice: kiri ikon mic (merah dicoret bila mute, headphone dicoret bila deafen); kanan avatar orang yang sedang bicara dengan cincin hijau (maks 3, lalu "+2").
- Peek: "#ngoding · Server Kampus · 5 orang" + [Mute] [Deafen] [Keluar].
- Tab Discord: daftar peserta (avatar, nama, sedang bicara, mute/deafen), tombol besar mute/deafen/keluar.
- DM/mention (FR-66, P1): avatar + nama pengirim + channel + cuplikan 1 baris; klik → `discord://-/channels/<guild_id>/<channel_id>` (DM: `@me`).

**Cadangan tanpa RPC (FR-67):**
- Status: Core Audio process object (`kAudioProcessPropertyIsRunningInput`, macOS 14.2+) menunjukkan Discord sedang memakai mikrofon → P2 "Discord · di voice".
- Mute/deafen: user mengatur keybind toggle di Discord (Settings → Keybinds), lalu memasukkan kombinasi yang sama di Dylan. Dylan mengirim kombinasi itu lewat `CGEvent` (butuh Accessibility). Status mute tidak diketahui, jadi tombolnya berupa toggle tanpa indikator.

- **AC:**
  - Masuk voice → Compact tampil < 1 s; orang bicara → cincin menyala < 300 ms.
  - Mute/deafen/keluar dari notch → status di Discord ikut berubah, dan sebaliknya.
  - DM masuk → P1 tampil; klik membuka DM yang tepat.
  - Discord ditutup/di-restart → Dylan menyambung ulang otomatis tanpa error ke user.
  - Mode Presentasi: nama peserta & isi DM tidak tampil.

### F18 — Notifikasi, Pesan & Panggilan (FR-68, FR-69, FR-82, FR-83)
- macOS tidak punya API resmi untuk membaca notifikasi app lain. Droppy memakai dua mode: "Standard" membaca store notifikasi macOS (butuh Full Disk Access), "Instant" memakai Screen Recording + Accessibility. **Spike T3.5** membandingkan:
  - (a) **Accessibility** pada banner Notification Center (proses `NotificationCenter`): baca nama app, judul, isi saat banner muncul. Banner sistem tetap tampil.
  - (b) **Store notifikasi** macOS: butuh Full Disk Access, isi lengkap bahkan bila banner dimatikan, tapi format dan lokasinya berubah antar versi macOS.
  - Pilih cara dengan izin paling sedikit yang andal. Screen Recording tidak dipakai. Bila keduanya tidak andal di macOS 27, FR-68 ditunda.
- Hanya app di daftar izin yang ditampilkan (default: WhatsApp, Telegram, Slack, Messages, Mail, Discord bila RPC tidak aktif). Isi tidak pernah disimpan ke disk; riwayat hanya menyimpan "app · waktu".
- Tampilan P1: ikon app + judul + cuplikan 1 baris; Peek: 3 baris + [Buka] [Tutup]. Beberapa notifikasi dari app yang sama digabung ("WhatsApp · 3 pesan").
- **Balas iMessage (FR-69):** di Peek notifikasi Messages ada kolom balasan. Kirim lewat AppleScript app Pesan (`send … to participant …`). Pengirim dicocokkan ke nomor/email lewat Contacts (izin Contacts). Bila tidak cocok persis satu kontak, kolom balasan diganti [Buka di Pesan]. Kolom balasan adalah satu-satunya tempat Dylan mengambil fokus keyboard, dan hanya setelah user mengkliknya.
- **Balas WhatsApp/Telegram (FR-69, Could):** hanya bila banner notifikasinya punya aksi "Reply" yang bisa dipicu lewat Accessibility (dicek di spike T3.5). Bila tidak, tombol [Buka chat].
- **Panggilan masuk (FR-82):** banner panggilan FaceTime/iPhone (Continuity) tampil sebagai P0 dengan [Terima] [Tolak], memakai cara yang sama dengan FR-68.
- **Kontrol meeting (FR-83):** saat Zoom/Teams sedang meeting, Peek menampilkan [Mute] [Kamera] [Share]. Zoom/Teams lewat item menu app (Accessibility); Google Meet lewat shortcut keyboard ke tab browser (⌘D mic, ⌘E kamera). Status mic dibaca dari indikator FR-71.
- **AC:** pesan WhatsApp masuk → P1 < 2 s; balas iMessage dari notch → pesan terkirim ke orang yang benar; Mode Presentasi menyembunyikan pengirim dan isi.

### F19 — Perangkat & Sistem (FR-40, FR-44, FR-70 s/d FR-72, FR-74)
- **Baterai & charging (FR-70):** event IOKit Power Sources. Charger dicolok → animasi pengisian (ikon petir + persentase + "penuh dalam 1 j 20 m"), P1. Dicabut → singkat. 100% → P1 "Baterai penuh". 20% → P1, 10% → P0. Low Power Mode → ikon kecil.
- **AirPods & Bluetooth (FR-44):** notifikasi connect/disconnect IOBluetooth → P1 dengan nama, ikon jenis perangkat (AirPods, headphone, mouse, keyboard, controller), dan baterai kiri/kanan/case bila tersedia. Sumber baterai ditentukan spike T0.6; bila tidak ada, tampil tanpa baterai.
- **HUD (FR-40):** volume, brightness layar, backlight keyboard tampil sebagai bar di telinga notch selama 1,5 s. Menyembunyikan HUD sistem butuh menangkap tombol lewat event tap (Accessibility) lalu mengatur nilainya sendiri; brightness & backlight keyboard tidak punya API publik. Spike T2.9 menentukan apa yang bisa; bila HUD sistem tidak bisa disembunyikan, fitur ditawarkan sebagai "HUD tambahan" saja atau dimatikan.
- **Indikator kamera & mikrofon (FR-71):** listener CoreMediaIO (kamera) dan Core Audio (mikrofon), event-based. Titik hijau/oranye di ujung telinga kanan selama dipakai. Peek menyebut app pemakai mikrofon bila diketahui dari Core Audio process object (macOS 14.2+); kamera hanya "sedang dipakai".
- **Focus (FR-72):** status Focus lewat `INFocusStatusCenter` (izin Focus). Nama Focus tidak tersedia lewat API publik; tampil "Focus aktif". API ini mungkin butuh entitlement Communication Notifications yang tidak bisa dipakai dengan ad-hoc sign; spike T2.10 memastikan. Bila tidak bisa, fitur ditunda (tidak memakai Full Disk Access hanya untuk ini).
- **Keep awake (FR-74):** `IOPMAssertionCreateWithName` (`PreventUserIdleDisplaySleep`). Durasi 15 m / 1 j / tanpa batas / sampai download selesai (FR-76). Indikator cangkir di Compact (P2) dan di menu bar. Mati otomatis saat baterai < 20% (bisa diatur).
- **AC:** colok charger → animasi < 1 s; AirPods tersambung → P1 dengan nama; Zoom memakai kamera → titik hijau menyala; keep awake 15 m → Mac tidak sleep selama 15 menit lalu kembali normal.

### F20 — Utilitas (FR-45, FR-46, FR-73, FR-75 s/d FR-77, FR-79, FR-81, FR-85 s/d FR-87)
- **Color picker (FR-73):** tombol di Home + hotkey ⌃⌥C → `NSColorSampler` (kaca pembesar sistem, tanpa Screen Recording). Hasil: swatch + hex disalin otomatis; klik untuk RGB/HSL; Mode Developer menambah format `Color(red:…)` SwiftUI dan CSS `rgb()`. Riwayat 20 warna.
- **Reminder (FR-75):** EventKit reminders yang jatuh tempo hari ini dan yang terlambat, di Home. Centang = selesai. Jatuh tempo → P1.
- **Tambah cepat (FR-85):** kolom di Home; `NSDataDetector` mencari tanggal/jam. Ada jam + kata "rapat/meeting" → event Kalender; selain itu → reminder. Pratinjau sebelum disimpan.
- **Cuaca (FR-45):** Open-Meteo tiap 30 menit (hanya saat layar menyala). Lokasi: kota manual (default) atau Location Services (opt-in). Home: ikon + suhu; Peek: kondisi + min/maks; Expanded: per jam 12 jam ke depan.
- **Progres download (FR-76):** FSEvents di `~/Downloads`. Chrome `.crdownload` dan Firefox `.part`: ukuran bertambah (progres tak tentu bila total tidak diketahui); Safari `.download`: progres dari `Info.plist` di dalam bundle bila tersedia. Selesai → P1 [Tampilkan di Finder] [Kirim ke Shelf]. Logika di `DylanCore/DownloadWatcher.swift` (unit test).
- **Scratchpad (FR-46):** satu catatan teks biasa, tersimpan otomatis, buka dengan hover + klik ikon pensil.
- **Hapus background (FR-77):** aksi di item gambar Shelf → Vision `VNGenerateForegroundInstanceMaskRequest` → PNG transparan baru di Shelf. Semua lokal.
- **Floating basket (FR-86):** saat drag file aktif, gerakan kursor kiri-kanan cepat (≥ 3 kali dalam 0,6 s) memunculkan keranjang di dekat kursor; isinya sama dengan Shelf.
- **OCR (FR-87):** aksi "Salin teks" di item gambar Clipboard/Shelf → `VNRecognizeTextRequest` (bahasa Indonesia & Inggris).
- **Kamera cermin (FR-79):** tombol di Home → preview kamera depan di Expanded; kamera mati saat panel ditutup atau setelah 60 s.
- **Waktunya berangkat (FR-81):** event dengan alamat → MapKit `MKDirections` (waktu tempuh dari lokasi saat ini, izin lokasi) → P1 "Berangkat 10 menit lagi · 25 m perjalanan".

### F21 — Widget Lock Screen (FR-80, eksperimental)
- macOS tidak mengizinkan app pihak ketiga menggambar di lock screen lewat API publik. App sejenis memakai fungsi privat SkyLight untuk menaruh jendela di atas lock screen.
- **Spike T4.1** menguji di macOS 27: apakah jendela bisa tampil di lock screen, apakah input (play/pause) bisa diterima, dan apakah ada efek samping (crash loginwindow, jendela tertinggal setelah unlock).
- Isi: jam besar, Now Playing (artwork + play/pause/next), baterai, cuaca. **Tidak ada** isi notifikasi atau data pribadi di lock screen.
- Mati secara default; tombol "Matikan" di Settings; nonaktif otomatis bila deteksi error saat lock.

### F22 — Tema & Kustomisasi (FR-78)
- Aksen: warna dominan artwork (Now Playing) dipakai untuk glow, progress bar, dan equalizer; bisa diganti warna tetap.
- Ukuran: Compact normal/kecil, Expanded normal/besar.
- Tema pill (layar tanpa notch): hitam (default) atau Liquid Glass (macOS 26+).
- Per-fitur: urutan & on/off tab; daftar app yang menyembunyikan notch saat di depan (mis. game, Keynote).
- Bentuk di notch fisik selalu hitam pekat (§3.3) supaya tetap menyatu dengan hardware.

### F23 — Screenshot (FR-88 s/d FR-94, design D38–D44)
- **Capture** lewat ScreenCaptureKit (izin Screen Recording, diminta saat capture pertama). Layar dibekukan dulu, lalu area dipilih di atas gambar beku: loupe membaca warna dari gambar itu, dan jendela Dylan dikecualikan dari capture.
- **Mode** dipilih di bar berbentuk notch (Area 1, Jendela 2, Layar 3, Scroll 4, Teks 5; Spasi ganti mode, Esc batal, ⇧ kunci rasio, ⌥ dari tengah, panah geser 1 px). Timer menunda pembekuan layar.
- **Hasil**: disalin ke clipboard (bisa diatur), file asli disimpan di riwayat `~/Library/Application Support/Dylan/Captures` (0700), opsional juga ke `~/Pictures/Dylan`. Notch P2 dengan thumbnail yang bisa diseret.
- **Studio & editor** memakai file yang sama; ekspor tidak pernah menimpa file asli, jadi edit bisa diulang.
- **Privasi**: semua lokal, tanpa jaringan; blur otomatis (opsional, default mati) memakai detektor rahasia yang sama dengan Clipboard; riwayat dihapus otomatis setelah masa simpan.

### F25 — Optimasi penyimpanan (FR-100 s/d FR-103)
- **Pindai** hanya di folder rumah user, tanpa root dan tanpa mengikuti symlink. Ukuran = ukuran yang dialokasikan di disk. Package (mis. Photos Library, Music Library, `.app`) tidak pernah dipecah dan tidak pernah dianggap "file besar". Folder yang dilindungi macOS (butuh Full Disk Access) dilewati dengan keterangan.
- **Dampak:** Rendah = dibuat ulang otomatis (cache, log, build); Sedang = perlu unduh/build ulang atau tidak bisa dipulihkan tapi bukan karya user (Trash, Archives); Tinggi = data milik user (Downloads, file besar, cadangan iPhone).
- **Hapus:** item berdampak Rendah dihapus permanen supaya ruangnya benar-benar kembali; item Sedang/Tinggi dipindah ke Trash (bisa dikembalikan), kecuali "Kosongkan Trash" itu sendiri. Path dicek ulang tepat sebelum dihapus (masih di dalam folder rumah, bukan symlink, bukan folder rumah itu sendiri).
- **Default:** hanya item Rendah yang dicentang, kecuali cache app yang sedang berjalan.

### F24 — Suhu & Kipas (FR-95 s/d FR-99, design D45–D49)
- **Baca** tanpa root: suhu dari sensor IOHID (`PMU tdie*` CPU, `PMU TP*g` GPU, `NAND` SSD, `gas gauge battery`), kipas dari SMC (`FNum`, `F<n>Ac/Mn/Mx/Md/Tg`). Polling 2 dtk saat tab Suhu terbuka, 10 dtk di latar hanya bila mode bukan Otomatis atau peringatan panas aktif. Spike M1 Pro (macOS 27.2): `F<n>Md` ui8, `F<n>Tg` flt, tanpa key `Ftst`.
- **Tulis** hanya lewat helper root (`Contents/Library/LaunchDaemons`, `SMAppService.daemon`). Klien divalidasi dengan code-signing requirement (identifier + team). Butuh build yang ditandatangani identitas Apple Development/Developer ID (`DYLAN_SIGN_IDENTITY`); build ad-hoc hanya memantau suhu.
- **Keamanan**: helper menjepit target ke `[F<n>Mn, F<n>Mx]`, mengembalikan kipas yang ia ambil ke Otomatis saat koneksi putus, SIGTERM, atau 10 dtk tanpa heartbeat. Dylan mengirim Otomatis sebelum sleep. Bila kipas sudah manual tanpa Dylan (mis. Macs Fan Control), Dylan menampilkan "Dikendalikan app lain" dan tidak mengubah apa pun sampai user memilih preset.
- **Mac tanpa kipas** (`FNum` = 0): bagian kipas, preset, dan menu Fan disembunyikan; tab Suhu tetap ada.

## 2.6 Bridge, CLI & Konfigurasi

**Socket:** `~/Library/Application Support/Dylan/dylan.sock`, mode 0600, satu JSON per baris, selalu berisi `"v": 1`.

```json
{"v":1,"type":"activity.start","id":"deploy","kind":"script","title":"Deploy staging","progress":0}
{"v":1,"type":"activity.update","id":"deploy","progress":0.6,"subtitle":"migrasi DB"}
{"v":1,"type":"activity.end","id":"deploy","result":"success","detail":"v2.4.1 · 3m 10s"}
{"v":1,"type":"notify","title":"Backup selesai","body":"12 GB"}
{"v":1,"type":"shell.start","shellPid":123,"cmd":"npm test","cwd":"/Users/gg/api","app":"com.microsoft.VSCode"}
{"v":1,"type":"shell.end","shellPid":123,"status":1}
{"v":1,"type":"hook","source":"claude","env":{"__CFBundleIdentifier":"com.microsoft.VSCode","TERM_PROGRAM":"vscode"},"payload":{}}
{"v":1,"type":"permission.ask","requestId":"r1","source":"claude","payload":{}}
{"v":1,"type":"shelf.add","paths":["/Users/gg/Desktop/a.png"]}
```

`payload` berisi JSON hook asli. Balasan untuk `permission.ask`: `{"decision":"allow"|"deny"|"passthrough","message":"…"}`.

**Perintah CLI:**

| Perintah | Fungsi |
|---|---|
| `dylan activity start <id> --title … [--subtitle …] [--progress 0..1] [--url …]` | Mulai aktivitas (P2) |
| `dylan activity update <id> [--progress …] [--subtitle …]` | Perbarui aktivitas |
| `dylan activity end <id> --success \| --failure [--detail …]` | Selesaikan aktivitas (P1) |
| `dylan notify <judul> [isi]` | Notifikasi singkat (P1) |
| `dylan run -- <perintah…>` | Jalankan perintah sebagai aktivitas; exit code diteruskan |
| `dylan shelf add <file…>` | Tambah file ke shelf |
| `dylan shell-init zsh` | Cetak skrip integrasi zsh |
| `dylan hook claude` / `dylan hook codex` | Dipanggil oleh hook agent |
| `dylan doctor` | Cek app jalan, socket, hook terpasang, versi `claude`, izin |

**Hook Claude Code yang dipasang** (digabung ke `~/.claude/settings.json`; `<APP>` = path absolut `Dylan.app`, ditulis literal saat pemasangan; CLI ada di `Contents/Helpers` karena `Contents/MacOS/Dylan` dan `…/dylan` adalah nama yang sama di disk case-insensitive):

```json
{
  "hooks": {
    "SessionStart":      [{ "hooks": [{ "type": "command", "command": "<APP>/Contents/Helpers/dylan hook claude", "timeout": 5 }] }],
    "UserPromptSubmit":  [{ "hooks": [{ "type": "command", "command": "<APP>/Contents/Helpers/dylan hook claude", "timeout": 5 }] }],
    "PreToolUse":        [{ "matcher": "*", "hooks": [{ "type": "command", "command": "<APP>/Contents/Helpers/dylan hook claude", "timeout": 5 }] }],
    "PostToolUse":       [{ "matcher": "*", "hooks": [{ "type": "command", "command": "<APP>/Contents/Helpers/dylan hook claude", "timeout": 5 }] }],
    "Notification":      [{ "hooks": [{ "type": "command", "command": "<APP>/Contents/Helpers/dylan hook claude", "timeout": 5 }] }],
    "PermissionRequest": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "<APP>/Contents/Helpers/dylan hook claude", "timeout": 60 }] }],
    "Stop":              [{ "hooks": [{ "type": "command", "command": "<APP>/Contents/Helpers/dylan hook claude", "timeout": 5 }] }],
    "SessionEnd":        [{ "hooks": [{ "type": "command", "command": "<APP>/Contents/Helpers/dylan hook claude", "timeout": 5 }] }]
  }
}
```

Event `StopFailure`, `PostToolUseFailure`, dan `SubagentStart/Stop` ditambahkan bila spike menunjukkan manfaatnya. Timeout hook dalam detik; timeout `PermissionRequest` harus lebih besar dari batas tunggu di Dylan (30 s).

**Integrasi zsh** (output `dylan shell-init zsh`, versi ringkas):

```zsh
_dylan_preexec() { _dylan_cmd=1; dylan _shell start --shell-pid $$ --cmd "$1" --cwd "$PWD" &! }
_dylan_precmd()  { local s=$?; [[ -n $_dylan_cmd ]] && dylan _shell end --shell-pid $$ --status $s &!; unset _dylan_cmd }
autoload -Uz add-zsh-hook
add-zsh-hook preexec _dylan_preexec
add-zsh-hook precmd  _dylan_precmd
```

**Mengenali app terminal.** Sumber utama adalah `__CFBundleIdentifier`, yang diwariskan macOS ke shell di dalam app. Cadangannya `TERM_PROGRAM`. Verifikasi semua nilai di spike T0.4.

| `__CFBundleIdentifier` / `TERM_PROGRAM` | App | Cara fokus |
|---|---|---|
| `com.microsoft.VSCode` / `vscode` | Visual Studio Code | `code <root project>` |
| `dev.zed.Zed` / `zed` | Zed | `zed <root project>` |
| `com.apple.Terminal` / `Apple_Terminal` | Terminal | Aktifkan app |
| `com.googlecode.iterm2` / `iTerm.app` | iTerm2 | Aktifkan app |
| `com.mitchellh.ghostty` / `ghostty` | Ghostty | Aktifkan app |

## 2.7 Izin, Info.plist & Entitlements

| Izin | Untuk | Kapan diminta |
|---|---|---|
Prinsip: izin hanya diminta saat fitur yang membutuhkannya dinyalakan, tidak pernah sekaligus di awal. Profil Umum tidak pernah meminta izin untuk fitur [Dev].

| Izin | Untuk | Kapan diminta |
|---|---|---|
| Kalender (`NSCalendarsFullAccessUsageDescription`) | Meeting berikutnya (FR-12), tambah cepat (FR-85) | Onboarding langkah 4, bila fitur dipilih |
| Reminder (`NSRemindersFullAccessUsageDescription`) | Reminder (FR-75, FR-85) | Saat fitur dinyalakan |
| Automation (`NSAppleEventsUsageDescription` + entitlement `com.apple.security.automation.apple-events`) | Kontrol Spotify & Music (FR-11, FR-60); kirim iMessage lewat Pesan (FR-69) | Saat pertama mengontrol media / membalas |
| Accessibility | Tempel otomatis dari clipboard (FR-20), HUD (FR-40), keybind Discord cadangan (FR-67), notifikasi & aksi Reply (FR-68, FR-69, FR-82), kontrol meeting (FR-83), isi password ke lock screen (FR-51) | Hanya saat fitur itu dinyalakan |
| Bluetooth (`NSBluetoothAlwaysUsageDescription`) | AirPods & perangkat Bluetooth (FR-44) | Saat fitur dinyalakan |
| Audio capture (`NSAudioCaptureUsageDescription`) | Visualizer nyata (FR-63), volume per app (FR-84) | Saat fitur dinyalakan |
| Kamera (`NSCameraUsageDescription` + entitlement `com.apple.security.device.camera`) | Kamera cermin (FR-79), Face Unlock (v2.0) | Saat pertama dibuka / pendaftaran wajah |
| Contacts (`NSContactsUsageDescription`) | Mencocokkan pengirim iMessage untuk balasan (FR-69) | Saat pertama membalas |
| Lokasi (`NSLocationUsageDescription`) | Cuaca otomatis (FR-45), waktunya berangkat (FR-81) | Opsional; default kota manual |
| Focus (`NSFocusStatusUsageDescription`) | Status Focus (FR-72) | Saat fitur dinyalakan; lihat catatan entitlement di §F19 |
| Full Disk Access | Hanya bila spike T3.5 memilih store notifikasi (FR-68 opsi b) | Opsional, dengan penjelasan |
| Password admin | Touch ID untuk `sudo` (FR-29) | Dijalankan sendiri oleh user di terminal |
| Password admin (Login Items & Extensions) | Helper kipas (FR-99), sekali saja | Saat memilih preset selain Otomatis pertama kali |
| Screen Recording | Hanya Screenshot (FR-88 s/d FR-91). Color picker tetap memakai `NSColorSampler`, visualizer memakai process tap | Saat capture pertama |
| Full Disk Access | Status Focus (FR-72): macOS 27 melindungi `~/Library/DoNotDisturb` | Opsional, dijelaskan di Settings → Perangkat |
| Jaringan | GitHub (lewat `gh`), cuaca, lirik, Spotify oEmbed/Web API, tukar token Discord | Opt-in per fitur |

- Tidak memakai sandbox, karena perlu `~/.claude`, `lsof`, socket, dan menjalankan `gh`/`git`. Hardened runtime + ad-hoc sign.
- `LSUIElement = YES` (tanpa ikon Dock).

## 2.8 Privasi & Keamanan

- Tidak ada telemetry. Semua data disimpan di `~/Library/Application Support/Dylan/` dengan izin 0600/0700.
- **Clipboard:**
  - Lewati item bertipe `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`, atau `org.nspasteboard.AutoGeneratedType`. Ini konvensi nspasteboard.org yang dipakai password manager.
  - Lewati app di daftar abaikan (default: 1Password, Bitwarden, Keychain Access, Passwords).
  - Item yang cocok pola rahasia hanya disimpan di memori, disamarkan (`ghp_••••a1b2`), dan hilang setelah 2 menit. Polanya: `ghp_`, `gho_`, `github_pat_`, `sk-`, `sk-ant-`, `AKIA[0-9A-Z]{16}`, `xox[abposr]-`, `-----BEGIN … PRIVATE KEY-----`, JWT, dan teks berlabel `password=`/`token=`/`secret=`.
  - Tersedia "Hapus semua" dan opsi "Hapus riwayat saat keluar".
- **Socket:**
  - Hanya bisa diakses user yang sama; pesan > 64 KB ditolak.
  - Dylan tidak pernah menjalankan perintah yang dikirim lewat socket. `dylan run` menjalankan perintah di proses CLI milik user, bukan di dalam app.
- **Agent:** Dylan tidak pernah mengizinkan apa pun secara otomatis; setiap izin butuh klik user. Tidak ada "izinkan selalu" di v1.0.
- **Edit config user** (`~/.claude/settings.json`, `~/.zshrc`): selalu dengan backup, diff, persetujuan, dan penulisan atomik.
- **Notifikasi, pesan, Discord:** isi hanya di memori selama tampil; riwayat hanya menyimpan "app · waktu". Token Discord & Spotify di Keychain. Dylan tidak membaca database chat app mana pun.
- **Artwork Spotify:** Spotify hanya memberi URL artwork, jadi Dylan mengunduhnya dari CDN Spotify sekali per lagu saat fitur Musik aktif.
- **Lirik & cuaca:** permintaan ke LRCLIB berisi judul/artis/album/durasi lagu; ke Open-Meteo berisi koordinat yang dibulatkan ke 2 desimal (± 1 km). Keduanya dijelaskan di Settings sebelum dinyalakan.
- **Kamera cermin:** hanya aktif selama panel terbuka (maks 60 s); tidak merekam atau menyimpan apa pun.
- **Lock screen:** hanya jam, musik, baterai, cuaca. Tidak ada notifikasi, pesan, atau data pribadi.
- **Tidak ada port jaringan.** Semua IPC lewat unix socket 0600. (Pelajaran dari Atoll: port RPC-nya sempat bisa diakses seluruh jaringan lokal.)
- **Face Unlock (v2.0):** embedding wajah dan password login hanya di Keychain milik Dylan; tidak pernah dikirim ke mana pun, ditampilkan, atau ditulis ke log. Kamera hanya aktif dalam jendela 8 detik setelah layar menyala saat terkunci, tidak pernah di latar.

---

# BAGIAN 3 — DESIGN BRIEF (untuk Claude Design)

> **Instruksi untuk Claude Design:** rancang UI aplikasi macOS **Dylan**, Dynamic Island untuk Mac yang ditujukan bagi semua pengguna Mac (musik, Discord, notifikasi, perangkat), dengan Mode Developer opsional untuk software engineer. Notch MacBook menjadi permukaan status yang hidup: tenang saat tidak ada apa-apa, informatif dalam satu lirikan saat ada yang penting. Acuan rasa: Dynamic Island iPhone dan Alcove (halus, organik, presisi). Hasil harus mudah diimplementasikan dengan **SwiftUI + AppKit** di macOS 15+.

## 3.1 Prinsip Desain

1. **Menyatu dengan hardware.** Closed, Compact, Peek, dan Expanded adalah satu bentuk hitam pekat yang tumbuh dari notch, bukan jendela yang muncul. Tepi atas menempel ke tepi layar; sudut bawah membulat (continuous).
2. **Satu lirikan.** Compact maksimal 2 informasi per sisi (ikon + nilai). Teks panjang hanya di Peek dan Expanded.
3. **Warna = status, bukan dekorasi.** Putih/abu untuk berjalan, hijau untuk selesai, merah untuk gagal, amber untuk butuh tindakan. Selain itu monokrom.
4. **Gerak bermakna.** Semua transisi memakai spring yang sama; perubahan ukuran selalu berasal dari notch. P0 boleh satu "pulse" lembut, tidak berkedip terus.
5. **Aman dipresentasikan.** User jelas tahu Mode Presentasi aktif, tapi indikatornya tidak mencolok bagi penonton.
6. **Ramah developer, tanpa membebani pengguna umum.** Angka memakai digit tabular. Di Mode Developer, path, perintah, dan timestamp memakai font mono dan mudah disalin. Di profil Umum tidak ada satu pun istilah teknis.
7. **Media sebagai pusat rasa.** Artwork, warna aksen, dan visualizer membuat notch terasa hidup; semua elemen lain tetap monokrom.

## 3.2 Daftar Layar & State

| ID | Layar | Isi utama |
|---|---|---|
| D1 | **Onboarding** | (1) Sambutan + ilustrasi notch yang hidup + pemilih bahasa (Indonesia/English) di pojok, (2) pilih profil: kartu "Umum" dan "Developer", (3) pilih fitur dengan pratinjau kecil per fitur, (4) izin untuk fitur terpilih dengan alasan singkat, (5) [Dev] pasang hook Claude Code: diff `settings.json` berwarna, tombol Pasang/Lewati, (6) [Dev] shell integration: tombol "Tambahkan ke ~/.zshrc" atau salin perintah |
| D2 | **Closed** | Hanya notch; tidak ada yang terlihat |
| D3 | **Compact – agent** | Varian: bekerja (glyph agent + spinner kecil · "Edit · AuthService.swift", dipotong), butuh izin (amber), menunggu input, selesai (✓ hijau · "4m 12s"), gagal (✗). Multi-sesi: badge angka |
| D4 | **Compact – command** | Berjalan ("npm test" · 1:23), sukses (✓ · 2m 13s), gagal (✗ exit 1) |
| D5 | **Compact – lainnya** | Now Playing (artwork + equalizer), meeting ("Standup · 5m"), timer (ring progres + mm:ss), port siap, CI berjalan/gagal, script dengan progress bar, charging |
| D6 | **Duo** | Dua aktivitas sekaligus, satu di tiap telinga (mis. agent di kiri, musik di kanan) |
| D7 | **Peek** | Saat hover: 1 baris detail + 1–3 aksi. Contoh: "Claude butuh izin: Bash `npm install zod`" · [Tolak] [Izinkan] [Terminal] |
| D8 | **Expanded – Home** | Kiri: Now Playing besar. Tengah: agenda hari ini (event berikutnya menonjol + Join). Kanan: timer/Pomodoro. Bawah: chip agent & command yang sedang berjalan |
| D9 | **Expanded – Agents** | Kartu izin di paling atas. Daftar sesi: project, app terminal, status, durasi, tool terkini. Sesi selesai menampilkan ringkasan + `+120 −8` + tombol "Buka project" |
| D10 | **Expanded – Shelf** | Grid file (thumbnail/ikon, nama). State drop zone saat drag ("Lepas untuk menyimpan"). Aksi per item + "Drag semua" |
| D11 | **Expanded – Clipboard** | Kolom cari, filter (Semua/Teks/Gambar/File/Pin), daftar item. Panel kanan: kartu smart detect (JWT ter-decode dengan `exp` relatif, JSON pretty, timestamp → tanggal), item rahasia tersamar, generator UUID/timestamp/hash |
| D12 | **Expanded – Dev** | Seksi Port (`:3000 node api-gateway` + aksi), GitHub (run per repo/branch: status + durasi; jumlah review request), Script widget (tile), Docker (v1.2) |
| D13 | **Expanded – Stats** | 4 grafik kecil (CPU, memori, jaringan, baterai) + proses teratas |
| D14 | **Mode Presentasi** | Compact dengan indikator `eye.slash`, plus contoh aktivitas yang sudah digeneralisasi |
| D15 | **Pill** (tanpa notch / monitor eksternal) | Sama seperti Compact/Expanded, tapi berbentuk pill mengambang 6 pt dari tepi atas. Opsi tema glass (macOS 26+) |
| D16 | **Settings** | Jendela Settings macOS standar dengan tab sesuai §F14 (Light & Dark), termasuk menu Bahasa di tab Umum |
| D17 | **Menu bar** (opsional) | Ikon template. Menu: Buka notch, Mode Presentasi, Jeda semua aktivitas, Settings, Keluar |
| D18 | **Riwayat aktivitas** | Di Home atau Agents: 20 aktivitas terakhir (ikon, judul, hasil, waktu) |
| D19 | **Face Unlock – pendaftaran** (v2.0) | Halaman peringatan ("Ini bukan Face ID", kapan aman dipakai) → preview kamera dengan cincin progres ala pendaftaran Face ID ("Gerakkan kepala perlahan memutar") → minta password login → selesai + tombol "Coba kunci sekarang" |
| D20 | **Face Unlock – Settings & riwayat** (v2.0) | Toggle, batas waktu kunci, Wi-Fi tepercaya, liveness, daftar 50 kejadian (waktu · hasil · skor), tombol "Hapus data wajah" |
| D21 | **Compact – dibuka dengan wajah** (v2.0) | P1 singkat: ikon `faceid` + "Dibuka dengan wajah". Varian gagal: "Face Unlock dimatikan · buka manual sekali" |
| D22 | **Touch ID untuk sudo** | Kartu di Settings → Terminal: status (aktif/belum), perintah + tombol Salin, catatan tmux |
| D23 | **Expanded – Media** | Artwork besar dengan glow aksen, judul/artis/album, progress bar, prev/play/next, shuffle, repeat, love, volume, pemilih output audio, baris "Putar cepat" (cover playlist yang di-pin), lirik berjalan (baris aktif tebal, baris lain 40%), volume per app (v1.1) |
| D24 | **Compact & Peek – lirik** | Compact: artwork + satu baris lirik berjalan (opsional). Peek: 3 baris lirik dengan baris aktif di tengah |
| D25 | **Compact & Peek – Discord voice** | Compact: ikon mic (normal/mute/deafen) + 1–3 avatar dengan cincin hijau saat bicara. Peek: "#channel · server · 5 orang" + [Mute] [Deafen] [Keluar] |
| D26 | **Expanded – Discord** | Daftar peserta (avatar, nama, bicara, mute/deafen), tombol besar mute/deafen/keluar, DM/mention terbaru. State belum tersambung: panduan buat Client ID 3 langkah |
| D27 | **Notifikasi & pesan** | P1: ikon app + judul + cuplikan. Peek: 3 baris + [Buka] [Tutup]; varian iMessage dengan kolom balasan; varian gabungan "WhatsApp · 3 pesan"; varian Mode Presentasi "Pesan baru · Discord" |
| D28 | **Panggilan & kontrol meeting** | P0 panggilan masuk (avatar, nama, [Tolak] merah, [Terima] hijau). Peek meeting: [Mute] [Kamera] [Share] dengan status |
| D29 | **HUD** | Volume, brightness, backlight keyboard: ikon + bar tipis di telinga notch; varian mute; muncul/hilang dalam 1,5 s |
| D30 | **Baterai & charging** | Animasi colok charger (petir + persentase + "penuh dalam 1 j 20 m"), cabut, penuh, 20% (amber), 10% (merah, P0), Low Power Mode |
| D31 | **AirPods & Bluetooth** | Animasi tersambung: ikon perangkat + nama + baterai kiri/kanan/case; varian tanpa baterai; varian terputus |
| D32 | **Indikator privasi & Focus** | Titik hijau (kamera) / oranye (mic) di ujung telinga; Peek "Zoom memakai mikrofon"; aktivitas singkat Focus aktif/mati |
| D33 | **Utilitas di Home** | Baris tombol: color picker, keep awake (cangkir), kamera cermin, scratchpad; kartu cuaca; daftar reminder dengan checkbox; kolom tambah cepat; download berjalan dengan progres |
| D34 | **Color picker** | Hasil: swatch + hex tersalin, varian RGB/HSL, riwayat 20 swatch |
| D35 | **Widget lock screen** (eksperimental) | Jam besar, Now Playing (artwork + play/pause/next), baterai, cuaca; di atas wallpaper lock screen |
| D36 | **Settings tambahan** | Tab Media, Discord, Notifikasi, Perangkat & Sistem, Utilitas (§F14); tab [Dev] tersembunyi di profil Umum |

## 3.3 Komponen & Token

- **Bentuk:** hitam `#000000` 100%, selalu (Light maupun Dark), supaya menyatu dengan notch. Radius bawah: Compact 10–12 pt, Peek 16 pt, Expanded 28–32 pt (continuous). Tema glass hanya untuk pill (D15).
- **Ukuran:** lihat §2.4. Telinga Compact ≤ 100 pt per sisi; tinggi Compact = tinggi notch.
- **Tipografi:** SF Pro (11–13 pt di Compact/Peek, 13–15 pt di Expanded). SF Mono untuk path, perintah, dan timestamp. Digit tabular untuk timer dan durasi.
- **Warna status:** berjalan = putih 85%; sukses = hijau sistem; gagal = merah sistem; butuh tindakan = amber/kuning sistem; info = biru sistem. Teks sekunder putih 55%.
- **Warna aksen media:** warna dominan artwork (saturasi dibatasi supaya kontras ≥ 4,5:1 di atas hitam), hanya untuk glow, progress bar, visualizer, dan lirik aktif. Indikator privasi memakai hijau/oranye sistem, sama seperti iOS.
- **Ikon:** SF Symbols. Agent memakai glyph netral (mis. `sparkle` atau `terminal`). Logo merek pihak ketiga (Spotify, Discord, WhatsApp) tidak digambar sendiri; pakai ikon app dari sistem (`NSWorkspace.icon(forFile:)`) bila app terpasang.
- **Gerak:** spring (response 0,35, damping 0,8) untuk perubahan ukuran; konten fade + blur 120 ms. Equalizer dan spinner berhenti saat Reduce Motion aktif.
- **Spacing:** 4 / 8 / 12 / 16 / 24.
- **Ikon app:** konsep "pulau" + notch: kapsul hitam di atas gradasi gelap dengan satu titik cahaya kecil (status), gaya squircle macOS.

## 3.4 Copy (Bahasa Indonesia & English)

Semua teks UI tersedia dalam dua bahasa (FR-18). Tombol ditulis dalam `[kurung]`. Untuk Claude Design: mockup utama memakai Bahasa Indonesia; sertakan minimal D3, D7, D25, dan D30 dalam versi English untuk mengecek panjang teks.

| Konteks | Bahasa Indonesia | English |
|---|---|---|
| Agent bekerja | **"Claude mengedit AuthService.swift"** / **"Claude menjalankan `npm test`"** | **"Claude is editing AuthService.swift"** / **"Claude is running `npm test`"** |
| Butuh izin | **"Claude butuh izin"** / "Bash: `npm install zod`" · [Tolak] [Izinkan] [Buka terminal] | **"Claude needs permission"** / "Bash: `npm install zod`" · [Deny] [Allow] [Open terminal] |
| Menunggu input | **"Claude menunggu jawabanmu"** | **"Claude is waiting for you"** |
| Agent selesai / gagal | **"Selesai · 4m 12s · +120 −8"** / **"Claude berhenti karena error"** | **"Done · 4m 12s · +120 −8"** / **"Claude stopped with an error"** |
| Command | **"npm test berjalan · 1:23"** / **"npm test gagal · exit 1 · 2m 13s"** / **"npm run build selesai · 48s"** | **"npm test running · 1:23"** / **"npm test failed · exit 1 · 2m 13s"** / **"npm run build done · 48s"** |
| Meeting | **"Standup mulai 5 menit lagi"** · [Join] | **"Standup starts in 5 min"** · [Join] |
| Port | **"localhost:5173 siap · web-admin"** | **"localhost:5173 is ready · web-admin"** |
| CI | **"CI gagal: build · feat/login"** / **"CI lulus · 6m"** | **"CI failed: build · feat/login"** / **"CI passed · 6m"** |
| CPU | **"node memakai 180% CPU · 2 menit"** · [Hentikan] | **"node is using 180% CPU · 2 min"** · [Stop] |
| Shelf kosong | **"Tarik file ke sini untuk menyimpannya sementara"** | **"Drop files here to keep them for later"** |
| Discord voice | **"#ngoding · 5 orang"** · [Mute] [Deafen] [Keluar] / "Kamu di-mute" | **"#coding · 5 people"** · [Mute] [Deafen] [Leave] / "You're muted" |
| Discord DM | **"Raka di #tugas-akhir"** / "ada yang mau review slide?" | **"Raka in #final-project"** / "anyone want to review the slides?" |
| Discord belum tersambung | **"Sambungkan Discord"** / "Buat app Discord gratis sekali saja (± 2 menit), lalu tempel Client ID-nya di sini." | **"Connect Discord"** / "Create a free Discord app once (about 2 minutes), then paste its Client ID here." |
| Notifikasi gabungan | **"WhatsApp · 3 pesan baru"** | **"WhatsApp · 3 new messages"** |
| Panggilan | **"Ibu menelepon"** · [Tolak] [Terima] | **"Mom is calling"** · [Decline] [Accept] |
| Charging / baterai lemah | **"Mengisi · 64% · penuh dalam 1 j 20 m"** / **"Baterai 10% · colok charger"** | **"Charging · 64% · full in 1 h 20 m"** / **"Battery 10% · plug in charger"** |
| AirPods | **"AirPods Pro tersambung"** · "L 80% · R 75% · Case 40%" | **"AirPods Pro connected"** · "L 80% · R 75% · Case 40%" |
| Privasi | **"Kamera sedang dipakai"** / "Zoom memakai mikrofon" | **"Camera in use"** / "Zoom is using the microphone" |
| Keep awake | **"Mac tetap menyala · 45 menit lagi"** | **"Keeping Mac awake · 45 min left"** |
| Color picker | **"#FF6B35 disalin"** | **"#FF6B35 copied"** |
| Download | **"Mengunduh Figma.dmg · 62%"** / "Figma.dmg selesai" · [Tampilkan] [Ke Shelf] | **"Downloading Figma.dmg · 62%"** / "Figma.dmg finished" · [Show] [To Shelf] |
| Putar cepat kosong | **"Tempel link playlist Spotify untuk memutarnya dari sini"** | **"Paste a Spotify playlist link to play it from here"** |
| Lirik tidak ada | (bagian lirik disembunyikan, tanpa pesan) | (lyrics section hidden, no message) |
| Clipboard rahasia | **"Disembunyikan · terhapus otomatis dalam 2 menit"** | **"Hidden · auto-deletes in 2 min"** |
| Mode Presentasi | **"Mode Presentasi aktif · detail disembunyikan"** | **"Presentation Mode on · details hidden"** |
| Face Unlock peringatan | **"Ini bukan Face ID"** / "Mac tidak punya kamera 3D. Wajah di video bisa membuka Mac-mu. Pakai hanya di tempat tepercaya; di tempat umum, pakai Touch ID." | **"This is not Face ID"** / "Your Mac has no 3D camera. A video of your face can unlock it. Use this only in trusted places; in public, use Touch ID." |
| Face Unlock berhasil / gagal | **"Dibuka dengan wajah"** / **"Face Unlock dimatikan. Buka kunci manual sekali untuk mengaktifkannya lagi."** | **"Unlocked with your face"** / **"Face Unlock turned off. Unlock manually once to turn it back on."** |
| Touch ID sudo | **"Pakai Touch ID untuk sudo"** / "Jalankan perintah ini sekali di terminal. Butuh password admin." | **"Use Touch ID for sudo"** / "Run this command once in Terminal. Requires your admin password." |
| Onboarding hook | **"Pantau Claude Code dari notch"** / "Dylan akan menambahkan beberapa hook ke `~/.claude/settings.json`. Hook lain milikmu tidak diubah, dan file lama di-backup." | **"Watch Claude Code from the notch"** / "Dylan will add a few hooks to `~/.claude/settings.json`. Your other hooks stay untouched, and the old file is backed up." |
| Pilih bahasa (onboarding) | **"Pilih bahasa"** · [Ikuti sistem] [Bahasa Indonesia] [English] | **"Choose language"** · [Use system language] [Bahasa Indonesia] [English] |
| Ganti bahasa butuh restart | **"Bahasa diganti. Buka ulang Dylan sekarang?"** · [Nanti] [Buka ulang] | **"Language changed. Relaunch Dylan now?"** · [Later] [Relaunch] |

## 3.5 Output yang Diharapkan dari Claude Design

1. Mockup D2–D9, D14, D23, D25, D29, dan D30 terlebih dahulu, di atas screenshot layar MacBook Pro 14" lengkap dengan menu bar. Lalu D10–D13, D15–D18, D24, D26–D28, D31–D36, dan D1.
2. **Spesifikasi gerak:** Closed → Compact (telinga keluar), Compact → Peek → Expanded, Duo split/merge, pulse P0, aktivitas selesai → kembali Closed, HUD masuk/keluar, animasi charging, AirPods tersambung, cincin bicara Discord, dan lirik bergulir. Sertakan durasi & kurva.
3. Spesifikasi komponen: ukuran, radius, state hover/pressed/disabled, aturan pemotongan teks.
4. Ikon app 1024 px + ikon menu bar template.
5. Catatan implementasi SwiftUI: nama SF Symbols, font, warna, dan di mana `matchedGeometryEffect` dipakai.

---

# BAGIAN 4 — TASK BREAKDOWN (untuk Claude Code)

> Kerjakan **berurutan**. Tiap task selesai bila acceptance criteria (AC) terpenuhi dan `./scripts/build.sh` berhasil. Logika murni (ActivityCenter, geometri, parser hook, merge settings, detector, filter command, link meeting, parser lsof, frame Discord, parser LRC, download watcher, profil) wajib punya unit test. Task bertanda [Dev] hanya untuk Mode Developer. Bagian yang butuh hardware atau izin diverifikasi lewat checklist Bagian 5.
>
> Sediakan dua alat debug sejak awal: `--snapshot <dir> [--lang id|en]` (render semua state D2–D36 ke PNG, per bahasa) dan `dylan debug emit <fixture>` (suntik event palsu).

## Phase 0 — Spike (wajib sebelum UI lengkap)

| Task | Isi | AC |
|---|---|---|
| **T0.1** Setup | SwiftPM: target `DylanCore`, app `Dylan`, CLI `dylan`, test. `scripts/build.sh` membundel `.app` (CLI di `Contents/Helpers`, karena "Dylan" dan "dylan" bentrok di disk case-insensitive), ad-hoc sign, opsi `--run` dan `--test` | `./scripts/build.sh --test --run` sukses; app jalan tanpa ikon Dock |
| **T0.2** Panel notch | NSPanel di atas notch: geometri dari safe area, level, Spaces, fullscreen, klik tembus di luar bentuk, animasi ukuran saat hover | Closed tak terlihat; menu bar tetap bisa diklik; animasi 120 fps; tidak mencuri fokus. Temuan di `docs/spike-notch.md` |
| **T0.3** Media | AppleScript + distributed notification untuk Spotify/Music (termasuk shuffle, repeat, volume, `play track <uri>`); uji pendekatan `mediaremote-adapter` untuk browser di macOS 27 + cek lisensinya | `docs/spike-media.md`: apa yang jalan + keputusan |
| **T0.4** [Dev] Hook Claude Code | `dylan hook claude` → socket. Rekam payload asli semua event jadi fixture. Uji `PermissionRequest`: apakah prompt terminal tertahan selama hook menunggu, format keputusan, perilaku timeout. Catat nilai `__CFBundleIdentifier`/`TERM_PROGRAM` di VS Code, Zed, dan Terminal | `docs/spike-claude-hooks.md` + fixture di `Tests/Fixtures/`; keputusan default FR-9 |
| **T0.5** Discord RPC | Sambung ke `discord-ipc-0`, handshake, `AUTHORIZE` dengan Client ID baru, tukar token (PKCE vs. Client Secret), `GET_SELECTED_VOICE_CHANNEL`, `SUBSCRIBE` speaking & voice state, `SET_VOICE_SETTINGS`, `NOTIFICATION_CREATE`. Uji juga cadangan keybind (FR-67) dan Core Audio process object untuk Discord | `docs/spike-discord.md`: alur yang jalan, batasan (10 server/channel, 1 pengontrol voice), fixture frame di `Tests/Fixtures/discord/` |
| **T0.6** Bluetooth & AirPods | Notifikasi connect/disconnect IOBluetooth; cari sumber baterai AirPods (kiri/kanan/case) dan perangkat lain; ukur biayanya | `docs/spike-bluetooth.md`: sumber baterai per jenis perangkat + keputusan |

## Phase 1 — v1.0 MVP

| Task | Isi | AC |
|---|---|---|
| **T1.1** ActivityCenter | Prioritas, slot Duo, antrean, durasi hasil, riwayat (di `DylanCore`) | Unit test semua aturan §2.4 |
| **T1.2** NotchView | State Closed/Compact/Peek/Expanded + tab bar, mengikuti desain di `design/` | D2–D8 sesuai desain; Reduce Motion dihormati |
| **T1.3** Interaksi | Hover, klik, swipe, hotkey ⌃⌥Space, Esc, klik di luar, fullscreen | AC §F1 |
| **T1.4** Bridge + CLI | Socket server, protokol §2.6, `activity`, `notify`, `run`, `doctor` | AC §F2; unit test protokol |
| **T1.5** [Dev] Agents | Parser hook → status sesi; Compact/Peek/D9; fokus app terminal; `git diff --shortstat`; ringkasan dari transcript | AC §F3 (tanpa FR-9), diuji dengan fixture + sesi asli |
| **T1.6** [Dev] Pasang hook | Merge/lepas `settings.json`, backup, diff (UI di onboarding & Settings) | Unit test merge: file kosong, sudah ada hook lain, sudah terpasang, JSON rusak (ditolak) |
| **T1.7** [Dev] Jawab izin (FR-9) | Alur §F3 langkah 1–5 | Sesuai keputusan T0.4; tidak pernah menahan prompt saat terminal di depan |
| **T1.8** [Dev] Command tracker | `shell-init zsh`, threshold, daftar abaikan, hasil | AC §F4 |
| **T1.9** Now Playing+ | Spotify & Music, FR-60 (shuffle, repeat, volume, love, putar cepat, aksen artwork), media browser bila T0.3 = Go | AC §F5 (kecuali lirik) |
| **T1.10** Meeting | EventKit, link meeting, countdown, Join | AC §F6; unit test parser link |
| **T1.11** Timer/Pomodoro | §F7 | Tetap akurat setelah sleep 5 menit |
| **T1.12** Mode Presentasi | §F12 + uji `sharingType` | Hasil uji Zoom/Meet di `docs/presentation-mode.md` |
| **T1.13** Settings, onboarding, bahasa, login item, menu bar | §F14, FR-18, D1, D16, D17; `Localizable.strings` id + en untuk semua copy §3.4 | Setting tersimpan antar restart; onboarding bisa dilewati; tidak ada string yang belum diterjemahkan (cek `xcstrings` + snapshot English) |
| **T1.14** Profil Umum/Developer | FR-17: `Profile.swift` menentukan provider, tab, izin, dan langkah onboarding yang aktif | Unit test; profil Umum tidak pernah menjalankan provider [Dev] atau meminta izinnya |
| **T1.15** Baterai & charging | FR-70, D30 | Colok/cabut charger tampil < 1 s; peringatan 20%/10% |
| **T1.16** AirPods & Bluetooth | FR-44, D31, sesuai keputusan T0.6 | Tersambung/terputus tampil < 2 s |
| **T1.17** Indikator kamera & mikrofon | FR-71, D32 | Zoom/FaceTime memakai kamera → titik hijau; mic → oranye; event-based tanpa polling |
| **T1.18** Polish & README | Ikon, README (build, profil, pasang hook, shell-init, CLI), checklist Bagian 5 bagian v1.0 | Lulus checklist |

## Phase 2 — v1.1 Everyday + Discord

| Task | Isi | AC |
|---|---|---|
| **T2.1** Clipboard + proteksi rahasia | §F8, §2.8 | Unit test detector & pola rahasia; item concealed tidak tersimpan |
| **T2.2** [Dev] Dev tools | Kartu smart detect + generator | JWT/JSON/timestamp tampil benar |
| **T2.3** Shelf | §F9 + drop zone + `dylan shelf add` | Drag masuk/keluar antar app dan antar Space |
| **T2.4** [Dev] Port | §F10 | Server Vite/Next terdeteksi < 15 s; Matikan bekerja |
| **T2.5** Stats + alert | §F13 | CPU idle Dylan tetap < 1% |
| **T2.6** Pill tanpa notch | FR-27, D15 | Diuji dengan monitor eksternal / mode clamshell |
| **T2.7** (Could) Deteksi screen share | FR-28 | Spike; aktifkan hanya bila andal |
| **T2.8** [Dev] Touch ID untuk `sudo` | §F16, D22 | AC §F16 |
| **T2.9** HUD | Spike: tangkap tombol volume/brightness/backlight (event tap), sembunyikan HUD sistem, atur nilai sendiri. Lalu FR-40, D29 | `docs/spike-hud.md` + keputusan; bila Go, HUD sistem tidak muncul lagi |
| **T2.10** Focus | Spike `INFocusStatusCenter` dengan ad-hoc sign, lalu FR-72 | Focus menyala/mati tampil, atau keputusan tunda dicatat |
| **T2.11** Discord | FR-65, FR-66 (sesuai T0.5), FR-67, D25, D26, panduan Client ID di Settings | AC §F17 |
| **T2.12** Lirik | FR-62, D23, D24, `LRCParser` | Unit test parser LRC; AC lirik §F5 |
| **T2.13** Output audio & volume per app | FR-61, FR-84 | Ganti ke AirPods dari notch; slider volume Spotify hanya mengubah Spotify |
| **T2.14** Color picker & keep awake | FR-73, FR-74, D34 | Warna tersalin; Mac tidak sleep selama durasi yang dipilih |
| **T2.15** Tema & kustomisasi | FR-78 | Aksen artwork, tema pill glass, sembunyikan saat app tertentu |

## Phase 3 — v1.2 Notifikasi & Integrasi

| Task | Isi | AC |
|---|---|---|
| **T3.1** [Dev] GitHub | FR-30 via `gh api` + ETag | Run gagal di branch aktif → P1 dalam < 90 s |
| **T3.2** [Dev] Script widget | FR-31, format §F11 | Contoh widget di `examples/widgets/` |
| **T3.3** [Dev] Codex | Spike `notify`, lalu FR-32 | Giliran Codex selesai tampil |
| **T3.4** [Dev] Docker (Could) | FR-33 | Restart/stop/logs bekerja |
| **T3.5** Spike notifikasi | Bandingkan Accessibility pada banner vs. store notifikasi (Full Disk Access) di macOS 27; cek aksi Reply WhatsApp/Telegram dan banner panggilan | `docs/spike-notifications.md` + keputusan Go/No-go FR-68/69/82 |
| **T3.6** Notifikasi di notch | FR-68, D27 | AC §F18; isi tidak pernah tertulis ke disk |
| **T3.7** Balas pesan & panggilan | FR-69, FR-82, D27, D28 | Balas iMessage ke orang yang benar; panggilan bisa diterima/ditolak |
| **T3.8** Kontrol meeting | FR-83, D28 | Mute/kamera Zoom & Meet dari notch |
| **T3.9** Reminder & tambah cepat | FR-75, FR-85, D33 | Centang reminder tersinkron ke app Reminders; "Rapat besok 10.00" jadi event |
| **T3.10** Cuaca | FR-45, D33 | Kota manual & lokasi otomatis; tidak ada request saat layar mati |
| **T3.11** Progres download | FR-76, `DownloadWatcher` | Unit test; download Chrome & Safari tampil dan selesai → P1 |

## Phase 4 — v1.3 Ekstra (pilih sesuai kebutuhan)

| Task | Isi | AC |
|---|---|---|
| **T4.1** Spike + widget lock screen | Uji fungsi privat SkyLight di macOS 27 (§F21), lalu FR-80, D35 | `docs/spike-lockscreen.md` + Go/No-go; bila Go, widget tampil dan hilang bersih setelah unlock |

Lainnya, pilih sesuai kebutuhan: FR-63 visualizer nyata, FR-64 Spotify Web API, FR-43 transform file, FR-77 hapus background, FR-86 floating basket, FR-87 OCR, FR-46 scratchpad, FR-79 kamera cermin, FR-81 waktunya berangkat, [Dev] FR-41 terminal (SwiftTerm), [Dev] FR-42 MCP server.

## Phase 5 — v2.0 Face Unlock (eksperimental)

| Task | Isi | AC |
|---|---|---|
| **T5.0** Spike Go/No-go | Uji di macOS 27, MBP 14": (a) apakah app bisa memakai kamera saat layar terkunci, (b) apakah input keyboard sintetis bisa mengisi password di lock screen, (c) trigger wake yang andal, (d) pilih model embedding wajah Core ML + lisensinya, (e) ukur salah-terima/salah-tolak pada wajahmu, foto, dan video. **Kerjakan di akun macOS uji, bukan akun utama** | `docs/spike-face-unlock.md` + keputusan Go/No-go. No-go bila (a) atau (b) gagal, atau foto bisa membuka |
| **T5.1** Pendaftaran | FR-50, D19 | Embedding tersimpan di Keychain; tanpa foto di disk |
| **T5.2** Policy & liveness | FR-52, FR-53 di `DylanCore` | Unit test semua syarat (waktu kunci, jumlah wajah, 1 percobaan, Wi-Fi) |
| **T5.3** Unlock | FR-51, FR-54, FR-55, D20, D21 | AC §F15 |

## 4.1 Prompt Pembuka untuk Claude Code

```
Baca PRD.md di root project. Kita bangun app macOS "Dylan" (Dynamic Island untuk
semua pengguna Mac, dengan Mode Developer opsional): Swift 6, SwiftUI + AppKit,
macOS 15+, SwiftPM (tanpa Xcode), tanpa dependensi pihak ketiga di v1.0.
Mulai dari Phase 0: kerjakan T0.1 sampai T0.6,
lalu berhenti dan laporkan temuan spike (docs/spike-*.md) sebelum lanjut ke Phase 1.
Desain UI ada di folder design/ (hasil Claude Design). Ikuti acceptance criteria tiap
task. Jangan pernah mengubah ~/.claude/settings.json atau ~/.zshrc tanpa backup dan
persetujuan saya.
```

---

# BAGIAN 5 — CHECKLIST UJI MANUAL

### Notch dasar
- [ ] Closed tidak terlihat; semua item menu bar di kiri/kanan notch tetap bisa diklik.
- [ ] Hover → Peek, klik → Expanded, Esc/klik di luar → tutup; swipe dua jari membuka/menutup.
- [ ] Mengetik di VS Code saat notch terbuka: ketikan tidak pindah ke Dylan.
- [ ] Video YouTube fullscreen: notch tersembunyi, tapi P0 tetap muncul.
- [ ] Sleep/wake, ganti Space, ubah resolusi: posisi tetap benar.
- [ ] CPU Dylan < 1% selama 1 jam idle (Activity Monitor); memori < 150 MB.

### Bahasa
- [ ] macOS berbahasa Indonesia → Dylan otomatis Indonesia; macOS berbahasa Inggris → English.
- [ ] Settings → Bahasa → English: notch, Settings, menu bar, dan onboarding berganti; aktivitas yang berjalan tetap utuh (setelah buka ulang bila diminta).
- [ ] Durasi dan tanggal mengikuti bahasa ("1 j 20 m" vs. "1 h 20 m", "Selasa" vs. "Tuesday").
- [ ] Tidak ada teks Indonesia yang tertinggal di mode English, dan sebaliknya (cek semua snapshot D2–D36).
- [ ] Teks English yang lebih panjang tidak terpotong jelek di Compact/Peek.

### Profil
- [ ] Onboarding profil Umum: tidak ada istilah developer, tidak ada permintaan izin untuk fitur [Dev], tab Agents/Dev tidak muncul.
- [ ] Ganti ke Developer di Settings: tab Agents/Dev muncul tanpa restart; kembali ke Umum: provider [Dev] berhenti.

### [Dev] Agents (Claude Code)
- [ ] Pasang hook dari onboarding: diff tampil, backup dibuat, hook lain yang sudah ada tetap utuh.
- [ ] Sesi di terminal VS Code: status bekerja, tool, dan file terkini benar.
- [ ] Dua sesi paralel (VS Code + Zed) tampil terpisah.
- [ ] Permission prompt saat sedang di Chrome: P0 muncul < 1 s; Izinkan dari notch → Claude lanjut.
- [ ] Permission prompt saat terminal di depan: prompt terminal muncul tanpa jeda.
- [ ] Selesai: durasi, `+x −y`, dan ringkasan benar; klik → jendela VS Code project yang tepat.
- [ ] Dylan di-quit: Claude Code tetap normal, tanpa pesan error hook.
- [ ] Lepas hook: `settings.json` kembali seperti semula (kecuali format/urutan).

### [Dev] Terminal & CLI
- [ ] `sleep 12 && false` → berjalan, lalu ✗ exit 1.
- [ ] `vim`, `ssh`, `npm run dev` tidak tampil sebagai command.
- [ ] Prompt zsh tidak terasa lebih lambat.
- [ ] `dylan run -- npm test` dan `dylan activity …` dari script tampil benar.

### Media, meeting, timer
- [ ] Spotify: ganti lagu, play/pause, seek, shuffle, repeat, volume dari notch.
- [ ] Pin playlist Spotify, quit Spotify, klik di notch → Spotify terbuka dan playlist mulai.
- [ ] Apple Music: love lagu dari notch tersimpan di app Music.
- [ ] (Bila T0.3 = Go) YouTube di Chrome: judul tampil, pause dari notch.
- [ ] (v1.1) Lirik: muncul untuk lagu populer, tetap sinkron setelah seek; lagu tanpa lirik → bagian lirik tersembunyi.
- [ ] (v1.1) Ganti output ke AirPods dari notch; volume per app hanya mengubah app itu.
- [ ] Event Zoom: countdown 10 menit, P0 di 1 menit, Join membuka Zoom.
- [ ] Pomodoro tetap akurat setelah laptop sleep 5 menit.

### Discord (v1.1)
- [ ] Settings → Discord: ikuti panduan Client ID, otorisasi di Discord, status "Tersambung".
- [ ] Masuk voice: Compact tampil; teman bicara → cincin hijau menyala.
- [ ] Mute/deafen/keluar dari notch → Discord ikut berubah; mute dari Discord → notch ikut berubah.
- [ ] DM masuk → P1; klik membuka DM yang tepat.
- [ ] Quit lalu buka lagi Discord → Dylan menyambung ulang sendiri.
- [ ] Tanpa Client ID: cadangan "Discord memakai mikrofon" + toggle mute lewat keybind bekerja.

### Perangkat & sistem
- [ ] Colok/cabut charger: animasi + persentase; baterai 20% (P1) dan 10% (P0).
- [ ] AirPods tersambung: nama + baterai (bila tersedia); terputus tampil singkat.
- [ ] Zoom memakai kamera → titik hijau; mic → titik oranye; keduanya hilang saat berhenti.
- [ ] (v1.1) HUD: tombol volume/brightness menampilkan HUD di notch, HUD sistem tidak muncul (bila T2.9 = Go).
- [ ] (v1.1) Keep awake 15 menit: Mac tidak sleep, lalu kembali normal.
- [ ] (v1.1) Color picker: hex tersalin dan benar dibanding Digital Color Meter.

### Notifikasi & utilitas (v1.2)
- [ ] WhatsApp/Telegram/Slack: notifikasi tampil di notch; app di luar daftar izin tidak tampil.
- [ ] Balas iMessage dari notch → terkirim ke orang yang benar.
- [ ] Panggilan FaceTime masuk → P0; Tolak/Terima bekerja.
- [ ] Reminder dicentang di notch → selesai juga di app Reminders.
- [ ] Download file besar di Chrome & Safari: progres tampil; selesai → P1.
- [ ] Cuaca sesuai kota; tidak ada request jaringan saat layar mati (cek Little Snitch/`nettop`).

### Mode Presentasi (sebelum meeting/demo)
- [ ] Hotkey ⌃⌥⌘H menyalakan/mematikan; indikator terlihat.
- [ ] Share layar penuh di Zoom & Meet: cek apa yang terlihat peserta, dan catat apakah `sharingType` berpengaruh.
- [ ] Clipboard terkunci; nama file/perintah/meeting tersembunyi; kartu izin tidak muncul.
- [ ] Notifikasi, DM Discord, dan nama peserta voice tampil generik tanpa isi.

### Toolkit (v1.1)
- [ ] Salin dari 1Password: tidak masuk riwayat.
- [ ] Salin token `ghp_…`: tersamar, hilang setelah 2 menit, tidak ada di file riwayat di disk.
- [ ] [Dev] Salin JWT/JSON/timestamp: kartu decode benar.
- [ ] Drag file ke notch, lalu ke Finder/Slack di Space lain.
- [ ] [Dev] `npm run dev` (Vite): "localhost:5173 siap" muncul; Matikan menghentikan server.
- [ ] [Dev] `node -e "while(1){}"` selama 60 s: alert CPU muncul; Hentikan bekerja.
- [ ] Monitor eksternal / clamshell: pill tampil di layar yang dipilih.

### [Dev] Integrasi (v1.2)
- [ ] Push commit yang membuat CI gagal: P1 "CI gagal" muncul < 90 s.
- [ ] Ada PR yang meminta review-mu: badge bertambah.
- [ ] Script widget contoh berjalan sesuai interval; script yang error tampil di tile.

### Lock screen (v1.3, eksperimental)
- [ ] (Bila T4.1 = Go) Kunci Mac: jam, musik, baterai, cuaca tampil; play/pause bekerja; setelah unlock widget hilang bersih.
- [ ] Tidak ada notifikasi atau data pribadi di lock screen.

### Touch ID & Face Unlock
- [ ] Touch ID untuk `sudo`: `sudo -k && sudo true` memunculkan Touch ID; di tmux dengan `pam-reattach` juga.
- [ ] (v2.0) Wajahmu → terbuka ≤ 2 s; lampu kamera mati ≤ 8 s.
- [ ] (v2.0) Foto wajahmu (cetak & layar HP), 20× → tidak pernah terbuka.
- [ ] (v2.0) Video wajahmu → catat hasilnya apa adanya di `docs/spike-face-unlock.md` (diperkirakan bisa membobol).
- [ ] (v2.0) Dua orang di depan kamera → tidak terbuka.
- [ ] (v2.0) Terkunci > 60 menit → tidak terbuka otomatis.
- [ ] (v2.0) Password login diganti → 1 percobaan gagal, fitur nonaktif.
- [ ] (v2.0) Setelah restart → wajib password (perilaku normal macOS).
- [ ] (v2.0) Matikan fitur → item Keychain embedding & password terhapus.
