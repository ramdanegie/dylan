# PRD — Dylan: Dynamic Island untuk Mac, khusus Software Engineer

| Field | Isi |
|---|---|
| Nama produk (kerja) | **Dylan** (*DY*namic is*LAN*d; boleh diganti) |
| Platform | macOS native (Swift 6 + SwiftUI/AppKit), macOS 15+, dioptimalkan untuk macOS 26+ |
| Perangkat utama | MacBook Pro 14" M1 Pro (ada notch, ProMotion 120 Hz), macOS 27 |
| Versi dokumen | 1.0 |
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

Dylan mengubah notch MacBook menjadi **pusat status untuk pekerjaan engineering**. Hal yang biasanya membuatmu bolak-balik pindah jendela muncul kecil di samping notch, lalu menyingkir sendiri setelah selesai:

- **Agent AI:** apa yang sedang dikerjakan Claude Code (dan nanti Codex), kapan agent **butuh izin**, dan kapan **selesai**. Izin bisa dijawab langsung dari notch.
- **Perintah panjang:** `npm test`, build, migrasi, deploy. Notch memberi tahu saat perintah selesai atau gagal, lengkap dengan durasi dan exit code.
- **Meeting:** hitung mundur sebelum meeting mulai, dengan tombol **Join**.
- **Dev harian:** dev server yang jalan di port mana, status GitHub Actions di branch-mu, clipboard history yang paham JWT/JSON/timestamp, dan shelf untuk file.
- **Standar Dynamic Island:** Now Playing (Spotify), timer/Pomodoro, stats sistem.
- **Eksperimental — Face Unlock:** membuka kunci Mac dengan wajah lewat kamera FaceTime, dengan batasan keamanan ketat dan hanya bila spike membuktikan bisa (§F15). Ditambah alternatif yang lebih aman: **Touch ID untuk `sudo`** (§F16).

Pembeda utama: **Live Activity API terbuka** lewat CLI `dylan`. Script apa pun bisa menampilkan progres di notch:

```bash
dylan activity start deploy --title "Deploy staging" --progress 0
dylan activity update deploy --progress 0.6 --subtitle "migrasi DB"
dylan activity end deploy --success --detail "v2.4.1 · 3m 10s"
```

Prinsip: **lokal, tanpa telemetry, gratis, ringan** (idle < 1% CPU), dan **aman saat screen share** lewat Mode Presentasi.

## 1.2 Latar Belakang & Masalah

1. **Notch adalah ruang mati.** Di MacBook Pro 14", area sekitar notch hanya berisi menu bar yang terpotong.
2. **Engineer banyak menunggu proses di background:** agent AI, test, build, CI, deploy. Untuk mengecek, kamu harus pindah ke terminal atau browser. Kalau lupa mengecek, Claude Code bisa menunggu izin 20 menit di terminal VS Code yang tertutup jendela lain.
3. **Meeting terlewat** saat sedang fokus coding.
4. **App referensi bagus, tapi tidak dibuat untuk engineer:**
   - Alcove dan DynamicLake fokus ke media, kalender, file, dan HUD.
   - Droppy paling lengkap dan sudah bisa memantau coding agent, tapi fitur itu satu dari 44 "droplet". Droppy juga berbayar.
   - Atoll gratis dan open-source, tapi berlisensi GPL-3.0 dan fiturnya generik.
5. **Risiko saat screen share:** notch yang menampilkan isi clipboard, nama file, atau judul meeting bisa ikut terlihat peserta. Ini penting saat demo aplikasi telemedicine.

## 1.3 Tujuan & Non-Tujuan

### Tujuan
1. Status agent AI, perintah panjang, dan CI terbaca dalam **satu lirikan**, tanpa pindah jendela.
2. **Tidak pernah melewatkan** permission prompt agent atau meeting.
3. Mempercepat pekerjaan kecil harian: clipboard + dev tools, shelf file, dev server.
4. Terasa **native dan halus** seperti Dynamic Island iPhone, dengan standar polish Alcove.
5. **Ringan, privat, offline.** Akses jaringan hanya untuk GitHub, dan itu opt-in.

### Non-Tujuan (tidak dikerjakan)
- Widget lock screen. Fitur ini butuh API privat SkyLight yang rawan rusak di tiap update macOS.
- "Face ID" yang setara iPhone. Mac tidak punya kamera TrueDepth (inframerah + kedalaman), jadi Face Unlock di Dylan hanya pengenalan wajah 2D dan **lebih lemah dari Touch ID maupun password** (§F15).
- Fitur hiburan dari Droppy: membalas iMessage/WhatsApp/Telegram, kontrol Apple TV, lirik, hapus background foto, suara keyboard mekanik.
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

**Persona sekunder:** engineer lain dengan pola kerja serupa, bila Dylan dibuka sebagai open-source.

## 1.5 User Stories

| ID | Sebagai engineer, saya ingin… | supaya… |
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

## 1.6 Lingkup per Rilis

| Rilis | Tema | Isi |
|---|---|---|
| **v1.0 MVP** | Notch + Agents | Shell notch (Compact/Peek/Expanded), Live Activity engine, CLI `dylan`, Claude Code, command tracker zsh, Now Playing, meeting berikutnya, timer/Pomodoro, Mode Presentasi, Settings & onboarding |
| **v1.1** | Dev Toolkit | Clipboard history + dev tools, shelf file, dev server/port, stats + alert proses boros, layar tanpa notch/monitor eksternal |
| **v1.2** | Integrasi | GitHub Actions & PR, script widget, Codex CLI, Docker |
| **v1.3** | Ekstra (Could) | HUD volume/brightness, terminal cepat di notch, MCP server, transform file, baterai AirPods, cuaca, scratchpad |
| **v2.0** | Face Unlock (eksperimental) | Buka kunci dengan wajah, **hanya bila spike T5.0 = Go**. Opt-in, mati secara default |

## 1.7 Requirement Fungsional (MoSCoW)

### v1.0 — Notch + Agents (MVP)

| ID | Requirement | Prioritas |
|---|---|---|
| FR-1 | **Jendela notch:** bentuk hitam yang menyatu dengan notch. Posisi dan ukuran dihitung dari geometri layar (§2.4), tidak di-hard-code | Must |
| FR-2 | **Empat state:** Closed (tak terlihat, seukuran notch) · Compact (live activity di "telinga" kiri/kanan notch) · Peek (saat hover: sedikit membesar, detail aktivitas teratas) · Expanded (panel dengan tab) | Must |
| FR-3 | **Interaksi:** hover → Peek (delay 150 ms, bisa diatur); klik → Expanded; swipe dua jari ke bawah/atas → buka/tutup; hotkey global ⌃⌥Space; Esc atau klik di luar → tutup. Tidak pernah mencuri fokus keyboard, kecuali saat mengetik di kolom pencarian Dylan | Must |
| FR-4 | **Live Activity engine:** prioritas P0–P3 (§2.4); maksimal 2 aktivitas tampil bersamaan (Duo), sisanya antre; hasil (selesai/gagal) tampil 5 detik lalu masuk riwayat (20 terakhir) | Must |
| FR-5 | **Fullscreen:** notch disembunyikan saat app di depan sedang fullscreen; hanya P0 (agent butuh izin, meeting mulai) yang tetap muncul | Must |
| FR-6 | **CLI `dylan` + Live Activity API:** `activity start/update/end`, `notify`, `run -- <cmd>`, `doctor` (§2.6) | Must |
| FR-7 | **Claude Code:** daftar sesi aktif (nama project, durasi); status bekerja (tool + file/perintah terkini), butuh izin, menunggu input, selesai (durasi, ringkasan, `+x −y` baris), gagal. Klik → fokus ke app terminal/editor tempat sesi berjalan | Must |
| FR-8 | **Pasang hook sekali klik:** gabungkan ke `~/.claude/settings.json` tanpa menyentuh hook lain; backup dulu; tampilkan diff; idempotent; bisa dilepas lagi | Must |
| FR-9 | **Jawab izin dari notch:** Izinkan / Tolak / Buka terminal, opt-in. Tidak boleh menahan prompt di terminal saat user sedang di terminal (§F3) | Should |
| FR-10 | **Command tracker (zsh):** perintah yang berjalan > 10 detik tampil sebagai aktivitas; saat selesai tampil ✓/✗ + exit code + durasi; ada daftar abaikan (vim, ssh, `npm run dev`, dll.) | Must |
| FR-11 | **Now Playing:** Spotify & Apple Music (wajib), player lain bila MediaRemote tersedia. Artwork, judul, play/pause/next/prev, seek. Compact: artwork + equalizer | Must |
| FR-12 | **Meeting berikutnya:** dari app Kalender macOS. Hitung mundur mulai 10 menit sebelum; tombol Join untuk link Zoom/Meet/Teams; jadi P0 saat 1 menit sebelum | Must |
| FR-13 | **Timer & Pomodoro:** timer cepat (preset + custom) dan Pomodoro 25/5 dengan hitungan siklus; tetap akurat setelah sleep | Should |
| FR-14 | **Tab Home:** Now Playing + agenda hari ini + timer + ringkasan agent/command yang sedang jalan | Must |
| FR-15 | **Settings, onboarding, login item**, ikon menu bar (opsional) | Must |
| FR-16 | **Mode Presentasi:** toggle lewat hotkey ⌃⌥⌘H dan menu; saat aktif, isi sensitif disembunyikan (§F12) | Must |

### v1.1 — Dev Toolkit

| ID | Requirement | Prioritas |
|---|---|---|
| FR-20 | **Clipboard history:** teks, gambar, file; cari; pin. Klik = salin; ⏎ = salin + tempel (bila izin Accessibility diberikan) | Must |
| FR-21 | **Smart detect + dev tools:** JSON (pretty/minify), JWT (decode header/payload, `exp` jadi waktu lokal), Unix timestamp ↔ tanggal, Base64, URL encode/decode, UUID, warna hex, path file, URL. Ditambah generator UUID, timestamp sekarang, dan hash | Must |
| FR-22 | **Proteksi rahasia:** abaikan item bertanda concealed/transient (password manager) dan app tertentu; item yang cocok pola token (§2.8) tidak disimpan ke disk, disamarkan, dan hilang setelah 2 menit | Must |
| FR-23 | **Shelf file:** drag file ke notch untuk disimpan; drag keluar ke mana pun; Quick Look, salin path, buka di editor, AirDrop, zip | Must |
| FR-24 | Screenshot baru otomatis masuk shelf | Should |
| FR-25 | **Dev server/port:** daftar port TCP yang listen milik user (port, proses, folder project); buka di browser, salin URL, matikan (dengan konfirmasi); aktivitas singkat "localhost:3000 siap" saat server baru muncul | Must |
| FR-26 | **Stats:** CPU, memori, jaringan, baterai (grafik kecil); alert bila satu proses > 150% CPU selama 60 detik, dengan tombol Hentikan | Should |
| FR-27 | **Layar tanpa notch / monitor eksternal:** bentuk pill di tengah atas; pilih layar (built-in, utama, semua) | Should |
| FR-28 | Mode Presentasi otomatis saat screen share terdeteksi (hanya bila spike T2.7 berhasil) | Could |
| FR-29 | **Touch ID untuk `sudo`:** cek apakah sudah aktif; bila belum, tampilkan perintah siap jalan untuk `/etc/pam.d/sudo_local` (§F16) | Should |

### v1.2 — Integrasi

| ID | Requirement | Prioritas |
|---|---|---|
| FR-30 | **GitHub:** run GitHub Actions di branch yang sedang kamu kerjakan (berjalan → aktivitas, gagal → P1), dan jumlah PR yang menunggu review-mu. Memakai login `gh` yang sudah ada | Must |
| FR-31 | **Script widget:** script di `~/.config/dylan/widgets/` dijalankan berkala; output JSON-nya jadi tile di tab Dev atau aktivitas (§F11) | Should |
| FR-32 | **Codex CLI:** giliran agent selesai → aktivitas; status berjalan bila datanya tersedia | Should |
| FR-33 | **Docker:** container berjalan/berhenti, restart/stop, buka log di terminal | Could |
| FR-34 | Agent lain (Cursor CLI, OpenCode) lewat adapter yang sama | Could |

### v1.3 — Ekstra

| ID | Requirement | Prioritas |
|---|---|---|
| FR-40 | HUD volume/brightness/backlight keyboard menggantikan HUD sistem (butuh Accessibility, perlu spike) | Could |
| FR-41 | Terminal cepat di notch (drop-down ala Quake, pakai SwiftTerm), bisa diserahkan ke Terminal/VS Code | Could |
| FR-42 | MCP server lokal: Claude Code bisa memanggil `notify`, `activity`, `shelf_add` | Could |
| FR-43 | Transform file di shelf: konversi/resize gambar, kompres video, gabung PDF, semuanya lokal | Could |
| FR-44 | Baterai AirPods/perangkat Bluetooth saat tersambung | Could |
| FR-45 | Cuaca (Open-Meteo, tanpa API key) | Could |
| FR-46 | Scratchpad: catatan cepat dalam satu hover | Could |

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
| CPU idle (Closed, tanpa aktivitas) | < 1% rata-rata. Polling hanya untuk fitur yang membutuhkannya (clipboard 0,5 s, port 10 s, GitHub 60 s) |
| CPU saat Expanded/animasi | < 10% di M1 Pro |
| Memori | < 150 MB |
| Animasi | 120 fps di ProMotion; spring (response 0,35 s, damping 0,8); hormati *Reduce Motion* |
| Latensi | Hover → Peek < 100 ms setelah delay; event hook → tampil < 300 ms |
| Hook Claude Code | `dylan hook` selesai < 50 ms untuk event biasa. **Fail-open:** bila Dylan mati atau hang, hook langsung keluar tanpa output dan tidak pernah mengganggu Claude Code |
| Stabilitas | Bertahan saat sleep/wake, ganti layar, ganti Space, dan restart Dylan. Crash Dylan tidak memengaruhi terminal/agent |
| Privasi | Tanpa telemetry/analytics. Tanpa jaringan kecuali GitHub (opt-in) dan cuaca (opt-in) |
| Keamanan | Socket hanya bisa diakses user sendiri (0600). Dylan tidak menjalankan perintah yang datang lewat socket. Edit file config selalu dengan backup |
| Aksesibilitas | Label VoiceOver di semua kontrol; navigasi keyboard di Expanded; kontras teks ≥ 4,5:1 |
| Kompatibilitas | macOS 15+, diuji di macOS 27, Apple Silicon (Intel tidak ditargetkan) |
| Bahasa | UI Bahasa Indonesia (default), string siap diterjemahkan ke Inggris |
| Face Unlock (v2.0) | Layar menyala → terbuka ≤ 2 s; kamera hanya aktif ≤ 8 s per percobaan (lampu hijau kamera menyala selama itu); 0 dari 20 percobaan pakai foto wajahmu berhasil membuka; embedding tidak pernah keluar dari Mac |

## 1.9 Metrik Sukses (pemakaian pribadi, 2 minggu)

- Dipakai setiap hari kerja tanpa pernah dimatikan karena mengganggu.
- ≥ 90% permission prompt Claude Code dijawab < 1 menit. Bandingkan dengan sebelum memakai Dylan lewat timestamp di transcript.
- Tidak ada meeting yang telat > 2 menit karena lupa.
- Tidak ada token/password yang tersimpan di riwayat clipboard di disk (dicek manual, §5).
- CPU idle < 1% di Activity Monitor selama 1 jam.

## 1.10 Asumsi, Risiko & Mitigasi

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Format hook Claude Code berubah | Status agent salah/kosong | Parser toleran (field tak dikenal diabaikan); fixture payload asli untuk unit test; `dylan doctor` memeriksa versi `claude` dan hook terpasang |
| Hook `PermissionRequest` yang menunggu jawaban menahan prompt di terminal | User yang sedang di terminal harus menunggu | Hook bertanya ke Dylan dulu. Bila terminal sesi sedang di depan, fitur mati, atau Mode Presentasi aktif, hook langsung lepas tanpa keputusan sehingga prompt normal muncul. Timeout 30 s. Tombol "Buka terminal" melepas seketika |
| Merusak `~/.claude/settings.json` milik user, yang sudah berisi banyak hook | Claude Code error | Merge JSON, backup bertanggal, tampilkan diff, validasi sebelum tulis, tulis atomik, tombol "Lepas hook", unit test merge |
| Akses MediaRemote (API privat) dibatasi sejak macOS 15.4 | Now Playing untuk browser/app lain tidak jalan | Spotify & Music lewat AppleScript + distributed notification (cukup untuk persona). MediaRemote hanya bonus (spike T0.3) |
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

## 1.11 Pertanyaan Terbuka

1. **Nama:** "Dylan" (*DY*namic is*LAN*d), atau ada usulan lain?
2. **Lisensi:** MIT seperti Cermin, atau GPL-3.0? MIT berarti tidak boleh menyalin kode Atoll/boring.notch (GPL). **Rekomendasi: MIT**, tulis dari nol, hanya pakai library MIT/BSD.
3. **Kalender:** apakah kalender kantor (Google Workspace) sudah tersambung ke app Kalender macOS? Kalau belum, FR-12 butuh itu dulu.
4. **Jawab izin dari notch (FR-9):** aktif secara default atau opt-in? **Rekomendasi:** opt-in, lalu putuskan default setelah spike T0.4.
5. **Terminal utama:** terminal terintegrasi VS Code, Zed, atau Terminal.app? Ini menentukan cara "fokus ke sesi".
6. **Repo GitHub yang dipantau:** cukup otomatis dari folder project yang dipakai Claude Code/terminal, atau perlu daftar manual juga?
7. **Cuaca & lock screen:** benar-benar tidak perlu? Keduanya dikeluarkan dari lingkup supaya fokus.
8. **Face Unlock:** apakah kamu menerima risikonya (bisa dibobol video wajahmu, password disimpan di Keychain)? Rekomendasi: kerjakan spike T5.0 dulu, lalu putuskan. Untuk tempat umum tetap pakai Touch ID.
9. **Model pengenal wajah:** Vision (bawaan Apple) hanya mendeteksi wajah, tidak mengenali *siapa*. Butuh model embedding wajah Core ML. Banyak model populer berlisensi non-komersial; kalau Dylan dibuka sebagai open-source MIT, pilih model yang lisensinya cocok.

## 1.12 Referensi Kompetitor

| | **Droppy** | **Atoll** | **DynamicLake** | **Alcove** |
|---|---|---|---|---|
| Harga | ±€8,92 sekali bayar (harga regional), trial 3 hari | Gratis, open-source GPL-3.0 (±5,1k ⭐) | Berbayar (Pro), ada plugin market | $12,99 sekali bayar, trial 72 jam |
| Kekuatan | Paling lengkap: file tray + transform, clipboard, 44 "droplet", **coding agents** (Claude Code/Codex/Cursor, bisa menjawab approval), kontrol meeting, Xcode builds, terminal di notch, MCP, Pomodoro | Gratis; stats sistem lengkap (CPU/GPU/memori/jaringan/disk), clipboard, color picker, tab terminal, gestur swipe, live activities, lock screen widgets | **SDK plugin** (DynamicLakeKit) + playground, **miniLake** (mode kecil), konversi audio/video/dokumen offline, AirDrop & share link, tema Liquid Glass | **Polish terbaik:** animasi halus, live activities ganda (Duo), HUD, notifikasi, lock screen widgets, **pill untuk layar tanpa notch**, kalender + "time to leave" |
| Kelemahan untuk engineer | Fitur sangat banyak, sebagian besar di luar kebutuhan dev; berbayar | GPL; minta banyak izin (Accessibility, Screen Recording, Camera); generik | Generik (media/file); berbayar | Hampir tanpa fitur dev; berbayar; mengandalkan API privat |

### Yang diadopsi Dylan (terbaik dari masing-masing)

| Fitur | Diambil dari | Versi Dylan |
|---|---|---|
| Pantau coding agent + jawab izin | Droppy (Agents) | Multi-sesi, `+x −y` dari git, fokus ke jendela terminal/editor yang tepat, fail-open, tidak menahan prompt terminal |
| Terminal di notch, Xcode builds | Droppy | Digeneralisasi jadi **command tracker** untuk semua perintah + Live Activity API untuk script apa pun |
| File tray/shelf, transform | Droppy, DynamicLake (DynaClip/DynaDrop) | Shelf + aksi dev (salin path, buka di editor); transform di v1.3 |
| Clipboard history | Droppy, Atoll | + smart detect dev (JWT, JSON, timestamp) + proteksi rahasia |
| Stats sistem | Atoll | + alert proses boros CPU (sering terjadi saat `node`/`docker` nyangkut) |
| Gestur swipe, hover | Atoll | Sama |
| Polish animasi, Duo, pill tanpa notch | Alcove | Sama, dan dijadikan acuan kualitas desain |
| Countdown meeting + Join | Droppy, Alcove | Sama, + P0 saat 1 menit sebelum |
| Plugin/extension | DynamicLake | Versi sederhana: **CLI + script widget**, tanpa SDK/marketplace |
| miniLake (mode ringkas) | DynamicLake | Pengaturan "Compact saja": Expanded hanya lewat klik/hotkey |

Face Unlock dan Touch ID untuk `sudo` tidak ada di keempat referensi; keduanya permintaan tambahan.

### Yang sengaja tidak diambil
Lock screen widgets, balas pesan, Apple TV, lirik, background removal, Mechey, Lid Fold, emoji picker, window snapping, uninstaller, app iPhone. Liquid Glass hanya jadi tema opsional untuk pill (v1.1+), bukan default.

---

# BAGIAN 2 — SPEC FITUR & TEKNIS

## 2.1 Arsitektur

```
 Claude Code hooks ─┐
 zsh preexec/precmd ┼─► dylan (CLI) ──unix socket──► Bridge ──┐
 script user ───────┘                                          ▼
                         Providers ──────────────────► ActivityCenter ──► NotchPanel (NSPanel + SwiftUI)
                         Media · Calendar · Timer       (prioritas,        ├─ Closed / Compact (telinga)
                         Clipboard · Shelf · Stats       antrean, Duo,     ├─ Peek (hover)
                         Ports · GitHub · Scripts        riwayat)          └─ Expanded (tab)
                                                               ▲
                                       PresentationMode ───────┘ (memfilter isi sensitif)
```

- **ActivityCenter** (logika murni di `DylanCore`, dengan unit test): menerima `Activity` dari semua sumber, lalu menentukan apa yang tampil di slot Compact, kapan Peek muncul otomatis, dan apa yang masuk riwayat.
- **Bridge:** server unix socket di dalam app. Semua sumber eksternal (hook, shell, script) lewat CLI `dylan`, jadi hanya ada satu protokol.
- **Providers:** satu file per fitur; masing-masing hanya aktif bila fiturnya dinyalakan.

## 2.2 Tech Stack

| Komponen | Pilihan | Alasan |
|---|---|---|
| Bahasa/UI | Swift 6, SwiftUI + AppKit (`NSPanel`) | Native, animasi 120 Hz |
| Build | SwiftPM + `scripts/build.sh` (membundel `.app`, ad-hoc sign) | Mac pengembang hanya punya Command Line Tools (sama seperti Cermin) |
| Target | macOS 15+; efek glass bila macOS 26+ | |
| Dependensi v1.0 | **Tidak ada** dependensi pihak ketiga | |
| Kalender | EventKit | Resmi |
| Media | AppleScript (Spotify, Music) + `DistributedNotificationCenter`; MediaRemote opsional | Resmi & stabil |
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
│   │   └── LsofParser.swift
│   ├── Dylan/                 # app
│   │   ├── App/               # DylanApp, AppModel, Onboarding, Settings
│   │   ├── Notch/             # NotchPanel, NotchView, Compact, Peek, Expanded, gestur, drop zone
│   │   ├── Bridge/            # SocketServer
│   │   ├── Providers/         # Agents, Commands, Media, Calendar, Timer, Clipboard, Shelf, Stats, Ports, GitHub, Scripts, FaceUnlock
│   │   └── UI/                # tab, komponen, theme
│   └── dylan/                 # executable CLI, dibundel ke Dylan.app/Contents/MacOS/dylan
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
| **P0 – urgent** | Agent butuh izin, meeting mulai ≤ 1 menit | Tampil walau ada app fullscreen; Peek otomatis 4 s; tetap di Compact sampai ditangani; suara opsional |
| **P1 – hasil** | Agent selesai, command selesai/gagal, CI gagal, meeting 10 menit lagi, server baru siap | Compact 5 s (gagal: 8 s), lalu masuk riwayat |
| **P2 – berjalan** | Agent bekerja, command berjalan, timer, CI berjalan, script/deploy | Compact selama berjalan |
| **P3 – ambient** | Now Playing, charging | Hanya bila ada slot kosong |

- Maksimal 2 slot (Duo). Slot diisi prioritas tertinggi; bila prioritasnya sama, yang terbaru menang.
- Beberapa sesi agent digabung jadi satu aktivitas di Compact ("3 agent · 1 butuh izin"); rinciannya di Peek/Expanded.
- Mode Presentasi mengganti isi aktivitas dengan teks generik, tapi status tetap terlihat.

## 2.5 Spec per Fitur

### F1 — Shell Notch (FR-1 s/d FR-5, FR-14, FR-27)
- Hover: delay 150 ms → Peek; kursor keluar area 300 ms → kembali. Klik/hotkey → Expanded. Swipe dua jari di area notch: ke bawah = buka, ke atas = tutup.
- Saat file di-drag dari mana saja dan mendekati notch, notch membuka tab Shelf sebagai drop zone (v1.1).
- Tab Expanded (urutan & on/off bisa diatur): **Home · Agents · Shelf · Clipboard · Dev · Stats**.
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

### F3 — Agents: Claude Code (FR-7, FR-8, FR-9)

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

### F4 — Command Tracker (FR-10)
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

### F5 — Now Playing (FR-11)
- Spotify: event `com.spotify.client.PlaybackStateChanged` + AppleScript untuk artwork URL, posisi, dan kontrol.
- Apple Music: event `com.apple.Music.playerInfo` + AppleScript.
- Player lain (browser): MediaRemote, bila spike T0.3 berhasil.
- Compact: artwork kecil di kiri, equalizer di kanan. Di v1.0 equalizer hanya animasi dekoratif, bukan analisis audio.
- Expanded: artwork, judul, artis, progress bar yang bisa digeser, prev/play/next.
- Swipe horizontal di area musik → next/prev.
- **AC:** ganti lagu di Spotify → notch berubah < 1 s; tidak ada polling saat musik berhenti.

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

### F8 — Clipboard & Dev Tools (FR-20 s/d FR-22)
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

### F10 — Dev Server & Port (FR-25)
- Tiap 10 s, hanya bila fitur aktif: jalankan `lsof -nP -iTCP -sTCP:LISTEN -F pcn`, ambil proses milik user, lalu cwd prosesnya → nama project.
- Daftar di tab Dev, contoh: `:3000  node  api-gateway  [Buka] [Salin] [Matikan]`.
- Matikan = SIGTERM, lalu tawarkan SIGKILL bila proses masih hidup setelah 3 s.
- Port baru → P1 "localhost:5173 siap · web-admin" (klik = buka di browser).
- Abaikan port milik sistem dan app umum (mis. ControlCenter di 5000/7000, Spotify, Docker internal). Daftarnya bisa diatur.

### F11 — Integrasi (FR-30 s/d FR-33)
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
  - Peek otomatis mati, kecuali P0 (tanpa detail).
  - Kartu izin agent tidak muncul; permintaan langsung dilepas ke terminal.
  - Indikator kecil `eye.slash` di Compact.
- Tambahan: coba `NSWindow.sharingType = .none` supaya panel tidak ikut tertangkap screen share. Verifikasi di Zoom & Meet.
- Hotkey sengaja dibedakan dari Privacy Curtain Cermin (⌃⌥⌘P) supaya tidak bentrok.

### F13 — Stats (FR-26)
- Sampling tiap 1 s hanya saat tab Stats terbuka. Di latar, sampling tiap 10 s untuk alert.
- Alert: satu proses > 150% CPU selama 60 s → P1 "node memakai 180% CPU · 2m", dengan tombol [Lihat] [Hentikan].
- Baterai: aktivitas singkat saat charger dicolok/dicabut (P3); peringatan di 20% dan 10% (P1).

### F14 — Settings & Onboarding (FR-15)
- Tab Settings:
  - **Umum:** login item, layar, hotkey, ikon menu bar.
  - **Tampilan:** ukuran, delay hover, animasi, Duo, mode "Compact saja".
  - **Live Activity:** durasi hasil, suara, prioritas per jenis.
  - **Agents:** status hook, pasang/lepas, jawab izin dari notch, timeout.
  - **Terminal:** shell integration, threshold, daftar abaikan.
  - **Clipboard:** riwayat, app yang diabaikan, hapus semua.
  - **Integrasi:** GitHub, script, Docker.
  - **Tentang**.
- Onboarding 4 langkah, semuanya bisa dilewati:
  1. Sambutan.
  2. Izin Kalender & Automation (Spotify/Music), dengan alasan yang jelas.
  3. Pasang hook Claude Code (tampilkan diff).
  4. Shell integration (tombol "Tambahkan ke ~/.zshrc", atau salin perintah) + pasang CLI ke `~/.local/bin/dylan`.

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

### F16 — Touch ID untuk `sudo` (FR-29)
- Mac persona sudah punya Touch ID (aktif untuk unlock), tapi `sudo` di terminal masih minta password. Ini alternatif biometrik yang **resmi dan aman**.
- Settings → Terminal menampilkan status: aktif bila `/etc/pam.d/sudo_local` berisi `pam_tid.so`.
- Bila belum aktif, tampilkan perintah untuk dijalankan sendiri (butuh password admin; Dylan tidak menulis ke `/etc` secara diam-diam):
  ```bash
  sed 's/^#auth/auth/' /etc/pam.d/sudo_local.template | sudo tee /etc/pam.d/sudo_local
  ```
  `sudo_local` bertahan saat update macOS.
- Bila terdeteksi `tmux`/`screen`, sarankan `pam-reattach` (Homebrew); tanpa itu Touch ID tidak muncul di dalam tmux.
- **AC:** setelah perintah dijalankan, `sudo -k && sudo true` di terminal VS Code memunculkan dialog Touch ID.

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

**Hook Claude Code yang dipasang** (digabung ke `~/.claude/settings.json`; `<APP>` = path absolut `Dylan.app`, ditulis literal saat pemasangan):

```json
{
  "hooks": {
    "SessionStart":      [{ "hooks": [{ "type": "command", "command": "<APP>/Contents/MacOS/dylan hook claude", "timeout": 5 }] }],
    "UserPromptSubmit":  [{ "hooks": [{ "type": "command", "command": "<APP>/Contents/MacOS/dylan hook claude", "timeout": 5 }] }],
    "PreToolUse":        [{ "matcher": "*", "hooks": [{ "type": "command", "command": "<APP>/Contents/MacOS/dylan hook claude", "timeout": 5 }] }],
    "PostToolUse":       [{ "matcher": "*", "hooks": [{ "type": "command", "command": "<APP>/Contents/MacOS/dylan hook claude", "timeout": 5 }] }],
    "Notification":      [{ "hooks": [{ "type": "command", "command": "<APP>/Contents/MacOS/dylan hook claude", "timeout": 5 }] }],
    "PermissionRequest": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "<APP>/Contents/MacOS/dylan hook claude", "timeout": 60 }] }],
    "Stop":              [{ "hooks": [{ "type": "command", "command": "<APP>/Contents/MacOS/dylan hook claude", "timeout": 5 }] }],
    "SessionEnd":        [{ "hooks": [{ "type": "command", "command": "<APP>/Contents/MacOS/dylan hook claude", "timeout": 5 }] }]
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
| Kalender (`NSCalendarsFullAccessUsageDescription`) | Meeting berikutnya | Onboarding langkah 2 |
| Automation (`NSAppleEventsUsageDescription` + entitlement `com.apple.security.automation.apple-events`) | Kontrol Spotify & Music | Saat pertama mengontrol media |
| Accessibility | Tempel otomatis dari clipboard (FR-20), HUD (FR-40), isi password ke lock screen (FR-51) | Hanya saat fitur itu dinyalakan |
| Kamera (`NSCameraUsageDescription` + entitlement `com.apple.security.device.camera`) | Face Unlock (v2.0) | Saat pendaftaran wajah |
| Password admin | Touch ID untuk `sudo` (FR-29) | Dijalankan sendiri oleh user di terminal |
| Screen Recording | **Tidak dipakai** | — |
| Jaringan | GitHub (lewat `gh`), cuaca | Opt-in |

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
- **Face Unlock (v2.0):** embedding wajah dan password login hanya di Keychain milik Dylan; tidak pernah dikirim ke mana pun, ditampilkan, atau ditulis ke log. Kamera hanya aktif dalam jendela 8 detik setelah layar menyala saat terkunci, tidak pernah di latar.

---

# BAGIAN 3 — DESIGN BRIEF (untuk Claude Design)

> **Instruksi untuk Claude Design:** rancang UI aplikasi macOS **Dylan**, Dynamic Island untuk Mac yang ditujukan bagi software engineer. Notch MacBook menjadi permukaan status yang hidup: tenang saat tidak ada apa-apa, informatif dalam satu lirikan saat ada yang penting. Acuan rasa: Dynamic Island iPhone dan Alcove (halus, organik, presisi). Hasil harus mudah diimplementasikan dengan **SwiftUI + AppKit** di macOS 15+.

## 3.1 Prinsip Desain

1. **Menyatu dengan hardware.** Closed, Compact, Peek, dan Expanded adalah satu bentuk hitam pekat yang tumbuh dari notch, bukan jendela yang muncul. Tepi atas menempel ke tepi layar; sudut bawah membulat (continuous).
2. **Satu lirikan.** Compact maksimal 2 informasi per sisi (ikon + nilai). Teks panjang hanya di Peek dan Expanded.
3. **Warna = status, bukan dekorasi.** Putih/abu untuk berjalan, hijau untuk selesai, merah untuk gagal, amber untuk butuh tindakan. Selain itu monokrom.
4. **Gerak bermakna.** Semua transisi memakai spring yang sama; perubahan ukuran selalu berasal dari notch. P0 boleh satu "pulse" lembut, tidak berkedip terus.
5. **Aman dipresentasikan.** User jelas tahu Mode Presentasi aktif, tapi indikatornya tidak mencolok bagi penonton.
6. **Ramah developer.** Angka memakai digit tabular. Path, perintah, dan timestamp memakai font mono dan mudah disalin.

## 3.2 Daftar Layar & State

| ID | Layar | Isi utama |
|---|---|---|
| D1 | **Onboarding** (4 langkah) | (1) Sambutan + ilustrasi notch yang hidup, (2) izin Kalender & Automation dengan alasan singkat, (3) pasang hook Claude Code: diff `settings.json` berwarna, tombol Pasang/Lewati, (4) shell integration: tombol "Tambahkan ke ~/.zshrc" atau salin perintah |
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
| D16 | **Settings** | Jendela Settings macOS standar dengan tab sesuai §F14 (Light & Dark) |
| D17 | **Menu bar** (opsional) | Ikon template. Menu: Buka notch, Mode Presentasi, Jeda semua aktivitas, Settings, Keluar |
| D18 | **Riwayat aktivitas** | Di Home atau Agents: 20 aktivitas terakhir (ikon, judul, hasil, waktu) |
| D19 | **Face Unlock – pendaftaran** (v2.0) | Halaman peringatan ("Ini bukan Face ID", kapan aman dipakai) → preview kamera dengan cincin progres ala pendaftaran Face ID ("Gerakkan kepala perlahan memutar") → minta password login → selesai + tombol "Coba kunci sekarang" |
| D20 | **Face Unlock – Settings & riwayat** (v2.0) | Toggle, batas waktu kunci, Wi-Fi tepercaya, liveness, daftar 50 kejadian (waktu · hasil · skor), tombol "Hapus data wajah" |
| D21 | **Compact – dibuka dengan wajah** (v2.0) | P1 singkat: ikon `faceid` + "Dibuka dengan wajah". Varian gagal: "Face Unlock dimatikan · buka manual sekali" |
| D22 | **Touch ID untuk sudo** | Kartu di Settings → Terminal: status (aktif/belum), perintah + tombol Salin, catatan tmux |

## 3.3 Komponen & Token

- **Bentuk:** hitam `#000000` 100%, selalu (Light maupun Dark), supaya menyatu dengan notch. Radius bawah: Compact 10–12 pt, Peek 16 pt, Expanded 28–32 pt (continuous). Tema glass hanya untuk pill (D15).
- **Ukuran:** lihat §2.4. Telinga Compact ≤ 100 pt per sisi; tinggi Compact = tinggi notch.
- **Tipografi:** SF Pro (11–13 pt di Compact/Peek, 13–15 pt di Expanded). SF Mono untuk path, perintah, dan timestamp. Digit tabular untuk timer dan durasi.
- **Warna status:** berjalan = putih 85%; sukses = hijau sistem; gagal = merah sistem; butuh tindakan = amber/kuning sistem; info = biru sistem. Teks sekunder putih 55%.
- **Ikon:** SF Symbols. Agent memakai glyph netral (mis. `sparkle` atau `terminal`); jangan memakai logo merek. Ikon app terminal (VS Code/Zed) boleh diambil dari sistem.
- **Gerak:** spring (response 0,35, damping 0,8) untuk perubahan ukuran; konten fade + blur 120 ms. Equalizer dan spinner berhenti saat Reduce Motion aktif.
- **Spacing:** 4 / 8 / 12 / 16 / 24.
- **Ikon app:** konsep "pulau" + notch: kapsul hitam di atas gradasi gelap dengan satu titik cahaya kecil (status), gaya squircle macOS.

## 3.4 Copy (Bahasa Indonesia)

- Agent bekerja: **"Claude mengedit AuthService.swift"** / **"Claude menjalankan `npm test`"**
- Butuh izin: **"Claude butuh izin"** / "Bash: `npm install zod`" · [Tolak] [Izinkan] [Buka terminal]
- Menunggu input: **"Claude menunggu jawabanmu"**
- Selesai: **"Selesai · 4m 12s · +120 −8"** · gagal: **"Claude berhenti karena error"**
- Command: **"npm test berjalan · 1:23"** / **"npm test gagal · exit 1 · 2m 13s"** / **"npm run build selesai · 48s"**
- Meeting: **"Standup mulai 5 menit lagi"** · [Join]
- Port: **"localhost:5173 siap · web-admin"**
- CI: **"CI gagal: build · feat/login"** / **"CI lulus · 6m"**
- CPU: **"node memakai 180% CPU · 2 menit"** · [Hentikan]
- Shelf kosong: **"Tarik file ke sini untuk menyimpannya sementara"**
- Clipboard rahasia: **"Disembunyikan · terhapus otomatis dalam 2 menit"**
- Mode Presentasi: **"Mode Presentasi aktif · detail disembunyikan"**
- Face Unlock peringatan: **"Ini bukan Face ID"** / "Mac tidak punya kamera 3D. Wajah di video bisa membuka Mac-mu. Pakai hanya di tempat tepercaya; di tempat umum, pakai Touch ID."
- Face Unlock berhasil: **"Dibuka dengan wajah"** · gagal: **"Face Unlock dimatikan. Buka kunci manual sekali untuk mengaktifkannya lagi."**
- Touch ID sudo: **"Pakai Touch ID untuk sudo"** / "Jalankan perintah ini sekali di terminal. Butuh password admin."
- Onboarding hook: **"Pantau Claude Code dari notch"** / "Dylan akan menambahkan beberapa hook ke `~/.claude/settings.json`. Hook lain milikmu tidak diubah, dan file lama di-backup."

## 3.5 Output yang Diharapkan dari Claude Design

1. Mockup D2–D9 dan D14 terlebih dahulu, di atas screenshot layar MacBook Pro 14" lengkap dengan menu bar. Lalu D10–D13, D15–D18, dan D1.
2. **Spesifikasi gerak:** Closed → Compact (telinga keluar), Compact → Peek → Expanded, Duo split/merge, pulse P0, dan aktivitas selesai → kembali Closed. Sertakan durasi & kurva.
3. Spesifikasi komponen: ukuran, radius, state hover/pressed/disabled, aturan pemotongan teks.
4. Ikon app 1024 px + ikon menu bar template.
5. Catatan implementasi SwiftUI: nama SF Symbols, font, warna, dan di mana `matchedGeometryEffect` dipakai.

---

# BAGIAN 4 — TASK BREAKDOWN (untuk Claude Code)

> Kerjakan **berurutan**. Tiap task selesai bila acceptance criteria (AC) terpenuhi dan `./scripts/build.sh` berhasil. Logika murni (ActivityCenter, geometri, parser hook, merge settings, detector, filter command, link meeting, parser lsof) wajib punya unit test. Bagian yang butuh hardware atau izin diverifikasi lewat checklist Bagian 5.
>
> Sediakan dua alat debug sejak awal: `--snapshot <dir>` (render semua state D2–D18 ke PNG) dan `dylan debug emit <fixture>` (suntik event palsu).

## Phase 0 — Spike (wajib sebelum UI lengkap)

| Task | Isi | AC |
|---|---|---|
| **T0.1** Setup | SwiftPM: target `DylanCore`, app `Dylan`, CLI `dylan`, test. `scripts/build.sh` membundel `.app` (CLI di `Contents/MacOS`), ad-hoc sign, opsi `--run` dan `--test` | `./scripts/build.sh --test --run` sukses; app jalan tanpa ikon Dock |
| **T0.2** Panel notch | NSPanel di atas notch: geometri dari safe area, level, Spaces, fullscreen, klik tembus di luar bentuk, animasi ukuran saat hover | Closed tak terlihat; menu bar tetap bisa diklik; animasi 120 fps; tidak mencuri fokus. Temuan di `docs/spike-notch.md` |
| **T0.3** Media | AppleScript + distributed notification untuk Spotify/Music; uji MediaRemote di macOS 27 | `docs/spike-media.md`: apa yang jalan + keputusan |
| **T0.4** Hook Claude Code | `dylan hook claude` → socket. Rekam payload asli semua event jadi fixture. Uji `PermissionRequest`: apakah prompt terminal tertahan selama hook menunggu, format keputusan, perilaku timeout. Catat nilai `__CFBundleIdentifier`/`TERM_PROGRAM` di VS Code, Zed, dan Terminal | `docs/spike-claude-hooks.md` + fixture di `Tests/Fixtures/`; keputusan default FR-9 |

## Phase 1 — v1.0 MVP

| Task | Isi | AC |
|---|---|---|
| **T1.1** ActivityCenter | Prioritas, slot Duo, antrean, durasi hasil, riwayat (di `DylanCore`) | Unit test semua aturan §2.4 |
| **T1.2** NotchView | State Closed/Compact/Peek/Expanded + tab bar, mengikuti desain di `design/` | D2–D8 sesuai desain; Reduce Motion dihormati |
| **T1.3** Interaksi | Hover, klik, swipe, hotkey ⌃⌥Space, Esc, klik di luar, fullscreen | AC §F1 |
| **T1.4** Bridge + CLI | Socket server, protokol §2.6, `activity`, `notify`, `run`, `doctor` | AC §F2; unit test protokol |
| **T1.5** Agents | Parser hook → status sesi; Compact/Peek/D9; fokus app terminal; `git diff --shortstat`; ringkasan dari transcript | AC §F3 (tanpa FR-9), diuji dengan fixture + sesi asli |
| **T1.6** Pasang hook | Merge/lepas `settings.json`, backup, diff (UI di onboarding & Settings) | Unit test merge: file kosong, sudah ada hook lain, sudah terpasang, JSON rusak (ditolak) |
| **T1.7** Jawab izin (FR-9) | Alur §F3 langkah 1–5 | Sesuai keputusan T0.4; tidak pernah menahan prompt saat terminal di depan |
| **T1.8** Command tracker | `shell-init zsh`, threshold, daftar abaikan, hasil | AC §F4 |
| **T1.9** Now Playing | Spotify & Music | AC §F5 |
| **T1.10** Meeting | EventKit, link meeting, countdown, Join | AC §F6; unit test parser link |
| **T1.11** Timer/Pomodoro | §F7 | Tetap akurat setelah sleep 5 menit |
| **T1.12** Mode Presentasi | §F12 + uji `sharingType` | Hasil uji Zoom/Meet di `docs/presentation-mode.md` |
| **T1.13** Settings, onboarding, login item, menu bar | §F14, D1, D16, D17 | Setting tersimpan antar restart; onboarding bisa dilewati |
| **T1.14** Polish & README | Ikon, README (build, pasang hook, shell-init, CLI), checklist Bagian 5 bagian v1.0 | Lulus checklist |

## Phase 2 — v1.1 Dev Toolkit

| Task | Isi | AC |
|---|---|---|
| **T2.1** Clipboard + proteksi rahasia | §F8, §2.8 | Unit test detector & pola rahasia; item concealed tidak tersimpan |
| **T2.2** Dev tools | Kartu smart detect + generator | JWT/JSON/timestamp tampil benar |
| **T2.3** Shelf | §F9 + drop zone + `dylan shelf add` | Drag masuk/keluar antar app dan antar Space |
| **T2.4** Port | §F10 | Server Vite/Next terdeteksi < 15 s; Matikan bekerja |
| **T2.5** Stats + alert | §F13 | CPU idle Dylan tetap < 1% |
| **T2.6** Pill tanpa notch | FR-27, D15 | Diuji dengan monitor eksternal / mode clamshell |
| **T2.7** (Could) Deteksi screen share | FR-28 | Spike; aktifkan hanya bila andal |
| **T2.8** Touch ID untuk `sudo` | §F16, D22 | AC §F16 |

## Phase 3 — v1.2 Integrasi

| Task | Isi | AC |
|---|---|---|
| **T3.1** GitHub | FR-30 via `gh api` + ETag | Run gagal di branch aktif → P1 dalam < 90 s |
| **T3.2** Script widget | FR-31, format §F11 | Contoh widget di `examples/widgets/` |
| **T3.3** Codex | Spike `notify`, lalu FR-32 | Giliran Codex selesai tampil |
| **T3.4** Docker (Could) | FR-33 | Restart/stop/logs bekerja |

## Phase 4 — v1.3 Ekstra (pilih sesuai kebutuhan)

FR-40 HUD (spike Accessibility + cara menyembunyikan HUD sistem), FR-41 terminal (SwiftTerm), FR-42 MCP server, FR-43 transform file, FR-44 AirPods, FR-45 cuaca, FR-46 scratchpad.

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
software engineer): Swift 6, SwiftUI + AppKit, macOS 15+, SwiftPM (tanpa Xcode),
tanpa dependensi pihak ketiga di v1.0. Mulai dari Phase 0: kerjakan T0.1 sampai T0.4,
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

### Agents (Claude Code)
- [ ] Pasang hook dari onboarding: diff tampil, backup dibuat, hook lain yang sudah ada tetap utuh.
- [ ] Sesi di terminal VS Code: status bekerja, tool, dan file terkini benar.
- [ ] Dua sesi paralel (VS Code + Zed) tampil terpisah.
- [ ] Permission prompt saat sedang di Chrome: P0 muncul < 1 s; Izinkan dari notch → Claude lanjut.
- [ ] Permission prompt saat terminal di depan: prompt terminal muncul tanpa jeda.
- [ ] Selesai: durasi, `+x −y`, dan ringkasan benar; klik → jendela VS Code project yang tepat.
- [ ] Dylan di-quit: Claude Code tetap normal, tanpa pesan error hook.
- [ ] Lepas hook: `settings.json` kembali seperti semula (kecuali format/urutan).

### Terminal & CLI
- [ ] `sleep 12 && false` → berjalan, lalu ✗ exit 1.
- [ ] `vim`, `ssh`, `npm run dev` tidak tampil sebagai command.
- [ ] Prompt zsh tidak terasa lebih lambat.
- [ ] `dylan run -- npm test` dan `dylan activity …` dari script tampil benar.

### Media, meeting, timer
- [ ] Spotify: ganti lagu, play/pause, seek dari notch.
- [ ] Event Zoom: countdown 10 menit, P0 di 1 menit, Join membuka Zoom.
- [ ] Pomodoro tetap akurat setelah laptop sleep 5 menit.

### Mode Presentasi (sebelum meeting/demo)
- [ ] Hotkey ⌃⌥⌘H menyalakan/mematikan; indikator terlihat.
- [ ] Share layar penuh di Zoom & Meet: cek apa yang terlihat peserta, dan catat apakah `sharingType` berpengaruh.
- [ ] Clipboard terkunci; nama file/perintah/meeting tersembunyi; kartu izin tidak muncul.

### Dev Toolkit (v1.1)
- [ ] Salin dari 1Password: tidak masuk riwayat.
- [ ] Salin token `ghp_…`: tersamar, hilang setelah 2 menit, tidak ada di file riwayat di disk.
- [ ] Salin JWT/JSON/timestamp: kartu decode benar.
- [ ] Drag file ke notch, lalu ke Finder/Slack di Space lain.
- [ ] `npm run dev` (Vite): "localhost:5173 siap" muncul; Matikan menghentikan server.
- [ ] `node -e "while(1){}"` selama 60 s: alert CPU muncul; Hentikan bekerja.
- [ ] Monitor eksternal / clamshell: pill tampil di layar yang dipilih.

### Integrasi (v1.2)
- [ ] Push commit yang membuat CI gagal: P1 "CI gagal" muncul < 90 s.
- [ ] Ada PR yang meminta review-mu: badge bertambah.
- [ ] Script widget contoh berjalan sesuai interval; script yang error tampil di tile.

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
