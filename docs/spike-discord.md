# Spike T0.5 — Discord RPC

Status: **sebagian.** Codec frame IPC (`DylanCore/DiscordFrame.swift`: opcode + panjang UInt32 LE + JSON) sudah ada dan diuji (frame terpotong di tengah header/payload, dua frame dalam satu chunk, opcode tidak dikenal).

Belum dikerjakan (butuh Client ID dari app Discord milikmu, lihat PRD §F17):
- `AUTHORIZE` → tukar token (PKCE atau Client Secret), `AUTHENTICATE`.
- `GET_SELECTED_VOICE_CHANNEL`, `SUBSCRIBE` speaking/voice state, `SET_VOICE_SETTINGS`, `NOTIFICATION_CREATE`.
- Batas app yang belum di-approve: 50 tester, 10 server/channel, 1 pengontrol voice.

Fitur Discord ada di v1.1, jadi belum menghalangi v1.0.
