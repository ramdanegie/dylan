# Ikon app Dylan — 2c Sirkuit

- `dylan-icon-1024.png`: master 1024 × 1024 (squircle 824 di kanvas transparan, grid macOS)
- `dylan-icon-small-1024.png`: master versi kecil (dipakai untuk 16, 16@2x, 32)
- `Dylan.iconset/`: semua ukuran untuk macOS

File @2x disimpan dengan akhiran `-2x` (karakter `@` tidak bisa dipakai di sini). Ganti namanya dulu, lalu buat `.icns`:

```bash
cd icon/Dylan.iconset
for f in *-2x.png; do mv "$f" "${f/-2x/@2x}"; done
cd ../..
iconutil -c icns icon/Dylan.iconset -o Resources/Dylan.icns
```

Lalu di `Info.plist`: `CFBundleIconFile = Dylan`.
