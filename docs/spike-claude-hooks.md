# Spike T0.4 — Hook Claude Code

Sumber: dokumentasi resmi https://code.claude.com/docs/en/hooks.md (Nov 2026). **Belum** direkam dari sesi asli: memasang hook mengubah `~/.claude/settings.json`, dan itu butuh persetujuanmu (Settings → Agents → Pasang hook, dengan diff + backup).

## Yang dipakai Dylan
- Field umum: `session_id`, `cwd`, `hook_event_name`. `Stop` membawa `last_assistant_message`, jadi Dylan tidak perlu membaca transcript (formatnya internal dan bisa berubah).
- `PermissionRequest` → stdout `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` atau `"deny"` + `"message"`. Tanpa output = prompt normal di terminal.
- Event yang stdout-nya masuk ke konteks Claude: `SessionStart`, `UserPromptSubmit` (dan beberapa via `additionalContext`). `dylan hook` tidak pernah menulis ke stdout kecuali keputusan izin.
- Payload dipangkas di CLI (`HookPayload.slim`): isi file dari `Write`/`Edit` tidak pernah dikirim ke app, dan pesan tetap < 64 KB.

## Terukur
- `dylan hook claude < PermissionRequest.json` dengan fitur "Jawab izin dari notch" mati: kembali dalam 20 ms tanpa output.
- Dylan tidak berjalan: hook keluar 0 tanpa output (fail-open).

## Masih terbuka (perlu sesi asli)
1. Apakah prompt terminal benar-benar tertahan selama hook `PermissionRequest` menunggu, dan berapa lama.
2. Nilai `__CFBundleIdentifier`/`TERM_PROGRAM` di VS Code, Zed, Terminal.
3. Ganti fixture di `Tests/DylanCoreTests/Fixtures/claude/` dengan payload rekaman.

Keputusan default FR-9: **opt-in** (mati sampai poin 1 terverifikasi).
