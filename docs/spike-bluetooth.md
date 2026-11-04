# Spike T0.6 — Bluetooth & AirPods

- Connect/disconnect: `IOBluetoothDevice.register(forConnectNotifications:)` + `register(forDisconnectNotification:)`. Notifikasi awal untuk perangkat yang sudah tersambung saat start diabaikan (2 detik pertama).
- Ikon: dari nama (`AirPods Pro`, `AirPods Max`, `AirPods`) lalu device class (audio → headphones, peripheral → keyboard/mouse).
- Fitur mati secara default (butuh izin Bluetooth).

Baterai: **belum terverifikasi.** Saat diuji tidak ada perangkat yang tersambung (`system_profiler SPBluetoothDataType` hanya menampilkan perangkat "Not Connected": beberapa AirPods, WH-1000XM5, Logitech Pebble). Langkah berikutnya: sambungkan AirPods, cek apakah `system_profiler` menampilkan `Left/Right/Case Battery Level`, lalu putuskan sumber datanya. Sampai itu, notch hanya menampilkan nama perangkat (PRD FR-44 mengizinkan ini).

Keputusan (v0.1): baterai dibaca dari `system_profiler SPBluetoothDataType -json` (tool publik, tanpa selector privat IOBluetooth), sekali per connect, 1,5 detik setelah event. Key: `device_batteryLevelLeft/Right/Case` untuk AirPods, `device_batteryLevelMain` untuk perangkat satu baterai. Parser diuji dengan fixture; **verifikasi live tetap butuh AirPods yang tersambung.**
