# Spike T3.5 — Notifikasi lewat Accessibility

Diuji di macOS 27.2 dengan banner dari `osascript -e 'display notification …'`.

- Proses: `NotificationCenter` (`com.apple.notificationcenterui`).
- Jendela banner: `AXWindow` subrole `AXSystemDialog`, judul "Notification Center".
- Banner: `AXGroup` subrole **`AXNotificationCenterBanner`**, identifier = UUID unik per banner.
  - `AXDescription`: `"<App>, <judul>, <subjudul>, <isi>"` → nama app = teks sebelum `", <judul>"`.
  - Anak `AXStaticText` dengan identifier `title`, `subtitle`, `body` (nilai di `AXValue`).
  - Aksi: `AXPress` (buka app), lalu aksi bernama `Name:Show Details`, `Name:Show`, `Name:Close` (format `Name:<nama>\nTarget:…`).
- `AXObserver` pada proses itu mengirim `AXWindowCreated` + `AXLayoutChanged` (elemen banner) saat banner muncul, dan `AXUIElementDestroyed` saat hilang. Tidak perlu polling.

Keputusan:
- Dylan membaca banner saat muncul, menampilkan P1 (pesan) atau P0 (panggilan), dan menyimpan isi hanya di memori.
- Balas, Terima/Tolak, dan Tutup memakai aksi milik banner itu sendiri. App asalnya yang mengerjakan; Dylan tidak mengirim pesan.
- Nama aksi `Reply`, `Accept`/`Answer`, `Decline` **belum terlihat langsung**. Banner uji tidak punya aksi itu, dan tidak ada panggilan/WhatsApp selama spike. Perlu dicek dengan WhatsApp/Pesan dan panggilan FaceTime asli.
- Butuh izin Accessibility. Fitur mati secara default.
