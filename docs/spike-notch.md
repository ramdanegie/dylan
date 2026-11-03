# Spike T0.2 — Panel notch

Diuji 4 Nov 2026 di MacBook Pro 14" (M1 Pro), macOS 27.2, layar bawaan skala 1800 × 1169 pt.

| Hal | Hasil |
|---|---|
| Geometri dari safe area | `safeAreaInsets.top` = 38 pt, `auxiliaryTopLeftArea`/`RightArea` = 790 pt → notch 220 × 38 pt di x = 900. Tidak ada angka yang di-hard-code (`NotchGeometry`, unit test). |
| Posisi panel | AppKit menggeser jendela supaya berada di bawah menu bar. **Wajib** override `constrainFrameRect(_:to:)` di `NotchPanel`, kalau tidak island muncul 38 pt di bawah notch. |
| Level & Spaces | `CGWindowLevelForKey(.mainMenuWindow) + 3`, `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`. Tampil di atas menu bar. |
| Klik tembus | Panel tetap sebesar Expanded; `ignoresMouseEvents` di-toggle dari frame island saat ini (monitor `mouseMoved` global + lokal, tanpa izin Accessibility). Menu bar di kiri/kanan notch tetap bisa diklik. |
| Fokus keyboard | Panel `nonactivatingPanel`; hanya bisa jadi key window saat Expanded (untuk Esc dan kolom timer). Hover/Peek tidak mengambil fokus. |
| Screen share | `sharingType = .none` → panel tidak ikut di `screencapture`. Untuk debug: `defaults write io.github.ramdanegie.dylan allowScreenCapture -bool true`. Perilaku di Zoom/Meet belum diuji (T1.12). |
| CPU | Idle 0,0% (0,01 s CPU dalam 30 s), RSS 69 MB. |

Belum diuji: 120 fps saat animasi (butuh Instruments/Xcode), monitor eksternal, mode clamshell.
