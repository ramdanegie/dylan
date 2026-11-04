# Ikon app Dylan — 3c Grafit · notch hidup

- `dylan-icon-1024.png`: master 1024 × 1024 (squircle 824 di kanvas transparan, grid macOS), dirender dari `#icon-3c` di `Dylan App Icon.dc.html` (Chrome headless, latar transparan)
- Satu master untuk semua ukuran: desain 3c memakai glyph yang sama di 16–1024
- `Dylan.iconset/`: semua ukuran untuk macOS

File @2x disimpan dengan akhiran `-2x` (karakter `@` tidak bisa dipakai di sini). Ganti namanya dulu, lalu buat `.icns`:

```bash
cd icon/Dylan.iconset
for f in *-2x.png; do mv "$f" "${f/-2x/@2x}"; done
cd ../..
iconutil -c icns icon/Dylan.iconset -o Resources/Dylan.icns
```

Lalu di `Info.plist`: `CFBundleIconFile = Dylan`.
