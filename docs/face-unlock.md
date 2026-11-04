# Face Unlock — rancangan (PRD §F15, v2.0 eksperimental)

> Ini bukan Face ID. Kamera Mac 2D, tanpa inframerah atau peta kedalaman. Face Unlock adalah fitur kenyamanan untuk tempat tepercaya, dan tetap **lebih lemah dari Touch ID maupun password**.

## Cara kerja Glance (referensi, Nov 2026)

Glance ([jonnyoo/glance](https://github.com/jonnyoo/glance), MIT, v1.2.0) adalah acuan paling matang:

| Aspek | Glance |
|---|---|
| Cara membuka kunci | Mengetik password tersimpan ke lock screen lewat `CGEvent` ke `.cghidEventTap` (butuh Accessibility). Field dikosongkan dulu (⌘→, ⌘⌫), lalu password dikirim per 20 karakter UTF-16, lalu Return |
| Penyimpanan password | Blob AES-GCM di Keychain, dibungkus kunci sesi 256-bit yang dilindungi `userPresence`; kunci di memori, terkunci lagi setelah 7 hari (default) |
| Cek terkunci | `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]`, fail-closed. Notifikasi lock hanya sebagai pemicu (bisa dipalsukan) |
| Pengenalan wajah | Vision (deteksi + alignment) → ArcFace Core ML 512-d; cocok bila similarity centroid dan sampel terbaik ≥ 0,66 |
| Liveness | Default "Light": hanya cue penolak (pantulan layar, bezel perangkat). "Heavy": + geometri 3D landmark, paralaks hidung, kedipan. README: **tidak andal menolak video**; fork melaporkan foto cetak matte lolos di mode Light |
| Pemicu | Wake & lock (default), tombol spasi (lewat IOHIDManager karena Secure Event Input), hover notch; jendela scan 3–10 s |
| Batasan | Tidak jalan di FileVault/login setelah restart. Overlay lock screen memakai SkyLight (API privat) |
| Yang tidak ada | Batas gagal, batas waktu sejak kunci, aturan jaringan, audit log. Threshold & mode liveness ada di `UserDefaults` (bisa diubah app lain) |

Proyek lain yang dipelajari: KINN-CH/FaceUnlock (kunci Secure Enclave, verifikasi password sebelum disimpan, "lock guard"), ArneshBanerjee/FaceUnlock (hanya kamera bawaan, kedipan buka-tutup-buka), c1osed1/FaceMac (GPL, tidak disalin).

## Yang membuat Dylan lebih baik

| # | Glance | Dylan |
|---|---|---|
| 1 | Liveness pasif, default Light; video bisa lolos | **Tantangan acak** tiap percobaan (mis. "lihat ke kiri, lalu kedip"), urutan dan arah diacak, jendela 6 s. Video rekaman tidak bisa mengikuti perintah acak. Cue penolak Glance tetap dipakai sebagai lapisan kedua |
| 2 | Identitas dicek sekali | Identitas dicek **di setiap frame tantangan** pada wajah yang sama (track ID); wajah hilang/berganti = gagal |
| 3 | Kamera apa pun | **Hanya kamera bawaan** (`AVCaptureDevice.DeviceType.builtInWideAngleCamera`); virtual/OBS/Continuity/USB ditolak |
| 4 | Tanpa batas gagal | Aturan ala Apple: **5 gagal → nonaktif** sampai unlock manual; wajib password bila 48 jam tanpa unlock password; tidak pernah setelah restart; maks **1** pengetikan password per sesi kunci |
| 5 | Tanpa batas waktu | Hanya bila terkunci **< 60 menit** (bisa diatur) dan bukan kunci manual < 10 detik yang lalu (grace: tidak langsung terbuka lagi saat kamu baru menekan ⌃⌘Q) |
| 6 | Tanpa aturan tempat | Opsional **hanya di Wi-Fi tepercaya**; mati otomatis saat Mode Presentasi |
| 7 | Setting di `UserDefaults` | Threshold, mode, dan status aktif disimpan di **blob terenkripsi** bersama data wajah; perubahan butuh Touch ID |
| 8 | Password diketik apa adanya | Password **diverifikasi** saat disimpan (OpenDirectory), modifier & Caps Lock dilepas dulu, status terkunci dicek ulang sebelum tiap batch, buffer di-nol-kan setelah dipakai |
| 9 | Tanpa jejak | **Audit log lokal** (waktu, hasil, skor, cue liveness; tanpa gambar) + ringkasan di notch setelah unlock: "Dibuka dengan wajah 14.02 · 2 gagal" |
| 10 | Signature ad-hoc mematikan izin Accessibility setelah rebuild (dilaporkan KINN-CH) | Deteksi `AXIsProcessTrusted() == false` dan pandu user memberi izin ulang; dokumentasikan sertifikat self-signed |

## Alur

1. **Pemicu:** `com.apple.screenIsLocked` dicatat sebagai waktu kunci. Saat layar menyala lagi (wake, lid, input), cek `CGSessionCopyCurrentDictionary` → benar-benar terkunci?
2. **Kebijakan** (`FaceUnlockPolicy`, DylanCore): semua syarat di atas. Ditolak → kamera tidak pernah menyala.
3. **Tantangan:** buat 2 langkah acak dari {lihat kiri, lihat kanan, lihat atas, kedip}. Tampilkan di island lock screen (butuh SkyLight, spike T4.1/T5.0).
4. **Kamera ≤ 6 s:** tiap frame → Vision (wajah, landmark, yaw/pitch, mata) → embedding → `LivenessChallenge` memeriksa urutan dan identitas.
5. **Lolos:** cek ulang terkunci → ketik password (CGEvent) → Return. **Gagal:** hitung gagal, tulis audit log.
6. Setelah unlock: P1 "Dibuka dengan wajah", atau "Face Unlock dimatikan · buka manual sekali".

## Status implementasi

| Bagian | Status |
|---|---|
| Kebijakan (`FaceUnlockPolicy`) + tantangan liveness (`LivenessChallenge`) + audit log | Ada, dengan unit test |
| Identitas | `VNGenerateImageFeaturePrintRequest` pada crop wajah. Model Apple, bagian dari macOS, jadi tanpa masalah lisensi. Ambang dipelajari dari sebaran frame pendaftaran sendiri (jarak terjauh × 1,1). Pendaftaran tanpa sebaran (foto diam) ditolak. Feature print bersifat umum (bukan model wajah khusus), karena itu identitas dicek di **setiap** frame tantangan. Unit test memakai vektor sintetis |
| Kamera + Vision | Hanya `builtInWideAngleCamera` (bukan Continuity/USB/virtual), ±10 fps, maks 8 s. Yaw/pitch dari `VNFaceObservation`, mata dari landmark, track ID dari IoU |
| Penyimpanan | Template, pengaturan, dan log disegel AES-GCM (`FaceVault`) di `face.sealed` (0600); kunci 256-bit di Keychain. Password di Keychain setelah diverifikasi OpenDirectory. Tidak ada gambar yang disimpan. "Hapus" menghapus semuanya |
| Pemicu & pengetikan | Kunci dicatat dari `com.apple.screenIsLocked`; percobaan saat layar menyala (`screensDidWake`) bila `CGSSessionScreenIsLocked`. Lolos → cek ulang kebijakan → ⌘→ ⌘⌫ → password per 20 unit UTF-16 (`.cghidEventTap`) → Return; buffer di-nol-kan |
| Instruksi tantangan | Diucapkan (AVSpeechSynthesizer, id/en), karena lock screen tidak bisa digambari tanpa panel SkyLight eksperimental |
| Transparansi | P1 "Dibuka dengan wajah · n gagal sebelumnya" setelah unlock; riwayat 50 kejadian di Settings (tanpa foto); "Matikan Face Unlock" di menu bar; ditolak saat Mode Presentasi |
| Belum diverifikasi | Arah tanda `yaw` dari Vision (kiri/kanan), skor feature print pada wajah asli vs orang lain, dan pengetikan ke lock screen. **Spike T5.0 bersama kamu di akun macOS uji**, bukan di akun utama |
