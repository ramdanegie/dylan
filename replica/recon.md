# Recon map: Glance (macOS) → Face Unlock Dylan

Scope: hanya alur face unlock Glance (daftar wajah, scan di lock screen, pengaturan). Bukan clone app Glance; yang diambil fungsi dan pola UX untuk Face Unlock Dylan (PRD §F15, FR-50–55).
For: Dylan sendiri (fitur eksperimental, mati default).
Date: 2026-11-07

Aturan: clean-room. Hanya sumber publik (situs, README, catatan rilis). Kode Glance tidak dibaca atau disalin, walau MIT. Model ArcFace Glance tidak dipakai (lihat Out of scope).

## Sources

| # | source | URL | notes |
| --- | --- | --- | --- |
| 1 | marketing site | https://www.tryglance.app/ | Identities (masker, kacamata, ekspresi, cahaya) bisa dimatikan tanpa dihapus; mode tampilan "Expanded"/"Minimal"; haptic + animasi; auto-lock sesi Touch ID |
| 2 | README | https://github.com/jonnyoo/glance | Pemicu wake/lock/spasi; liveness Off/Light/Heavy (5 cue, jendela ±2 s); pilih kamera per layar; Face Lab tersembunyi; enrollment 9 arah; MIT |
| 3 | changelog | https://github.com/jonnyoo/glance/releases | 1.2.0: toleransi 2 s non-match, feedback arah saat kepala terlalu jauh, session lock "Never"/30 hari, General Settings terkunci saat sesi terkunci, ganti password tersimpan. 1.1.0: kamera di onboarding, kualitas capture dalam %. 1.0.1: indikator posisi kepala live |
| 4 | studi sebelumnya | docs/face-unlock.md | Perbandingan Glance v1.2.0 vs Dylan (10 poin), dibuat saat F15 dirancang |
| 5 | kode Dylan | Sources/Dylan/Providers/FaceUnlockProvider.swift, Sources/DylanCore/FaceUnlock.swift, FaceMatch.swift, Sources/Dylan/App/FaceEnrollWindow.swift | kondisi Dylan sekarang |

## Core loop

Daftar wajah sekali → Mac terkunci → layar menyala → wajah cocok + lolos liveness → password diketik ke lock screen → terbuka.

## Screens (Glance)

| ID | screen | how to reach | purpose | key components | states seen |
| --- | --- | --- | --- | --- | --- |
| S01 | Onboarding + peringatan | buka pertama kali | izin Kamera, Accessibility, Touch ID; peringatan "bukan Face ID"; pilih kamera | kartu izin, picker kamera | belum diizinkan, diizinkan |
| S02 | Enrollment 9 arah | onboarding / Settings → identity baru | tangkap embedding dari 9 pose | preview kamera, indikator posisi kepala live, feedback arah, kualitas % | mencari wajah, pose kurang, terlalu jauh, selesai |
| S03 | Password | setelah S02 | simpan password Mac, dibungkus Touch ID | field password, prompt Touch ID | salah, tersimpan, ganti |
| S04 | Scan di notch lock screen | wake / lock / spasi | animasi scan di notch (Expanded/Minimal), pill di Mac tanpa notch | island, animasi scan, haptic | scanning, berhasil, gagal, hover untuk ulang |
| S05 | Settings: Identities | Settings | daftar kartu identity, toggle aktif, edit/hapus | kartu (nama, ikon aksesori), toggle | kosong, banyak, satu dimatikan |
| S06 | Settings: Unlock | Settings | liveness Off/Light/Heavy, pemicu, kamera per layar, animasi, mode tampilan | segmented, toggle, picker | — |
| S07 | Settings: Security | Settings | auto-lock sesi (Never…30 hari), hapus data/password | picker, tombol hapus | sesi terkunci (General terkunci) |
| S08 | Face Lab | About → klik ikon 5× | konsol debug skor & cue liveness | angka skor live, cue | — |

## Flows

```
F01 Daftar wajah pertama
    S01 -> S02 -> S03 -> selesai
    happy path: ±4 klik + putar kepala 9 arah
    edge: dua wajah, cahaya gelap, kepala terlalu jauh, password salah

F02 Buka kunci
    lock/wake/spasi -> S04 scanning -> cocok + liveness -> ketik password -> terbuka
    happy path: 0 klik (lihat kamera)
    edge: non-match singkat (toleransi 2 s), foto/layar HP (cue penolak), video (lolos — diakui README), sesi Touch ID kedaluwarsa

F03 Tambah identity (kacamata/masker/orang lain)
    S05 -> S02 -> S05
    edge: identity dimatikan tidak ikut dicocokkan

F04 Ganti password tersimpan
    S07/S03 -> Touch ID -> password baru

F05 Uji pengenalan
    S08 -> skor live
```

## Components

| component | variants | states | used on |
| --- | --- | --- | --- |
| Island scan | expanded, minimal, pill | scanning, success, fail, retry-hover | S04 |
| Kartu identity | biasa, kacamata, masker | aktif, mati | S05 |
| Preview kamera + indikator kepala | — | mencari, pose kurang, terlalu jauh, cukup | S02 |
| Prompt Touch ID | — | minta, ditolak | S03, S07 |

## Inferred data model

```
Identity   id, name, embeddings[512-d], enabled, createdAt
           evidence: situs (kartu identity + toggle), README "toggle each on/off"
           confidence: high
Session    key (userPresence), unlockedAt, autoLockAfter (never…30 hari)
           evidence: README, changelog 1.2.0
           confidence: high
Settings   liveness (off|light|heavy), triggers {wake, lock, space}, camera per display, animations, displayMode
           evidence: README, situs
           confidence: high
```

Relationships: Settings 1-n Identity; Session membungkus password + embeddings.

## Dylan vs Glance (celah)

Dylan sudah lebih ketat di keamanan (tantangan acak, cek identitas tiap frame, 5 gagal, 48 jam, 1 ketik per kunci, Wi‑Fi tepercaya, audit log, password diverifikasi). Celah nyata ada di **kenyamanan dan kualitas pendaftaran**:

1. **Satu template saja.** Glance: banyak identity (kacamata, masker, cahaya) + toggle. Dylan gagal bila wajah beda dari saat daftar.
2. **Gagal di satu frame buram.** `LivenessChallenge.feed` langsung `wrongPerson` bila satu frame < ambang. Glance 1.2.0 memberi toleransi 2 s. Bisa diadopsi tanpa melemahkan: langkah hanya dihitung pada frame yang cocok, track wajah tetap wajib sama.
3. **Pendaftaran bebas.** Dylan: "putar kepala" 20 frame tanpa panduan; bisa saja 20 frame menghadap lurus. Glance: 9 arah, indikator posisi live, feedback "terlalu jauh", kualitas %.
4. **Cue penolak tidak ada di kode.** docs/face-unlock.md janji "cue penolak Glance tetap dipakai" (pantulan layar, bezel perangkat), tapi `FaceCamera` belum mendeteksinya.
5. **Tidak bisa coba lagi tanpa tidur-bangun layar.** Pemicu Dylan hanya `screensDidWake`. Glance: lock, wake, spasi, hover notch.
6. **Tidak ada UI di lock screen.** Dylan hanya suara. Glance: island scan di lock screen (SkyLight). Dylan sudah punya panel SkyLight di `LockScreenProvider` (FR-80).
7. **Ganti password = daftar ulang total.** Glance 1.2.0 bisa ganti password tersimpan saja.
8. **Tidak ada uji pengenalan.** Glance punya Face Lab. Dylan punya log, tapi skor feature print belum pernah diukur (docs: "belum diverifikasi").
9. **Haptic** saat berhasil/gagal: Dylan tidak ada.

## Feature matrix

See `features.csv`. Belum ada di Dylan — must: 3, should: 5, could: 5. Sudah setara: 4. Skip: 6.

## Out of scope

- **Model ArcFace 512-d.** Bobot model ArcFace/insightface umumnya lisensi non-komersial; Dylan tetap `VNGenerateImageFeaturePrintRequest` (model Apple).
- **Liveness Off/Light.** Lebih lemah dari tantangan acak Dylan; tidak diadopsi.
- **Kamera eksternal/Continuity.** Ditolak sengaja (docs #3: kamera virtual bisa memutar video).
- **Auto-update Glance, swipe settings, "show in menu bar".** Dylan sudah punya sendiri.
- **Login setelah restart/FileVault.** Batasan macOS, sama di Glance.

## Size

Screens 8 (Glance), flows 5, entities 3. Yang diadopsi menyentuh 4 file inti + Settings + lokalisasi.
Hard parts: (1) migrasi vault terenkripsi dari 1 template ke banyak identity tanpa merusak data lama, (2) panel island di lock screen (SkyLight privat, rapuh antar versi macOS), (3) pemicu tombol spasi di lock screen (Secure Event Input → IOHIDManager → izin Input Monitoring baru).
Size: **M** untuk semua; **S** untuk must + should tanpa UI lock screen dan tombol spasi.
