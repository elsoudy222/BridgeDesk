# BridgeDesk MVP — Plan (Mac + Windows, from scratch)

Status: 2026-11-05 — user chose **new build from scratch, MVP only** (not a TwinDesk fork), platforms **Mac + Windows** first. Name: **BridgeDesk** — chosen 2026-11-05 after DuoDesk was rejected for a GitHub name collision (9 repos, including a TwinDesk fork doing the same thing). Package: `com.bridgedesk.app`. Project dir: `~/workspace/projects/bridgedesk/app`.
Inspiration: TwinDesk (GPL-3.0, 1217 files, Mac/Windows/Linux/Android) — this is an independent, clean-room MVP inspired by the idea, not a copy of its code.

## v1 — in scope (the core magic, nothing else)

1. **Discovery + pairing on same Wi-Fi**
   - mDNS/Bonjour discovery on LAN, device shows name + OS + IP.
   - Pairing with 6-digit PIN shown on one device, entered on the other.
   - TLS-encrypted channel after pairing; paired devices remembered, unpair from settings.
   - No account, no cloud, no telemetry in v1.
2. **One mouse + keyboard across the edge**
   - Push mouse off the right/left edge of one screen, it appears on the other, keyboard follows.
   - Configurable edge (left/right), hotkey to force-switch back, lock/sleep remote on disconnect.
   - Latency target on LAN: <20ms for mouse moves.
3. **Shared clipboard — text first**
   - Copy text on one, paste on the other. Images/files via clipboard in v1.1, not v1.
4. **File send**
   - Drag-and-drop a file onto the paired device / Send file button, progress + verify, save to Downloads folder. No shared-folder sync in v1.

## v1 — out of scope (v2 later)

Screen sharing / extended display, remote app windows, phone/Android, calls/texts/notifications, camera/mic sharing, ReZume (continue where you left off), Wake-on-LAN, Mesh (more than 2 devices).

## Recommended stack

- **Flutter desktop (macOS + Windows) for UI + app logic** — single Dart codebase, leverages user's 3 years Flutter/Dart. UI: device list, pairing, settings (edge, hotkey, clipboard on/off), file-transfer progress.
- **Native helpers for what Flutter cannot do alone:**
  - macOS: Swift — CGEventTap to capture mouse/keyboard, CGEventPost to inject, Accessibility + Input Monitoring permissions.
  - Windows: C++ — low-level hooks + SendInput to inject, Raw Input to capture.
  - Shared protocol in Dart: TCP/TLS sockets, JSON control messages + binary frames for mouse/file chunks.
- **Discovery:** mDNS via `multicast_dns` / Bonjour on macOS, plus manual IP entry as fallback.
- **Clipboard:** platform channels to NSPasteboard (macOS) / Win32 clipboard (Windows).
- **Files:** chunked transfer over the same TLS connection, SHA-256 verify per file.

Why not Electron like TwinDesk? TwinDesk is JS/Electron + Rust helpers. Flutter fits this user, gives one UI codebase, and the hard part is the native input lane either way — that part is native in both stacks.

## Permissions / gotchas to handle in v1

- macOS: app must ask for Accessibility + Input Monitoring; unsigned build needs `xattr -dr com.apple.quarantine` / Open Anyway on first launch. Code signing later.
- Windows: unsigned installer triggers SmartScreen "Run anyway"; input injection needs the app running with normal user rights for most cases, UAC-elevated windows are a known v1 limitation.
- Both devices must be on the same Wi-Fi in v1; no Bluetooth / no-cloud relay yet.
- Clipboard loops must be guarded (ignore our own clipboard writes).

## Milestones

- M0: name + repo scaffold, Flutter macOS+Windows shells run, pairing UI skeleton. ✅ Done 2026-11-05.
- M1: discovery + PIN pairing + TLS channel working Mac <-> Windows. ✅ Done 2026-11-05 — see "M1 design decisions" below. Verified on this Linux VM with `flutter analyze` (No issues found) and `flutter test` (30 tests, all passed, including a full TLS pairing handshake on loopback). macOS/Windows binaries still need to be run on the user's own Mac/Windows — the VM cannot build them.
- M2: mouse/keyboard edge crossing working both directions.
- M3: clipboard text + file send working, end-to-end test checklist.

## M1 design decisions (2026-11-05)

- **Discovery:** `bonsoir` 7.1.6 (mDNS advertise + browse). `multicast_dns` was rejected: it can only browse, not advertise, so a peer would never be found. Service type `_bridgedesk._tcp`; TXT record carries `id` (stable device id), `os`, `fp` (full 64-hex certificate fingerprint). Self-advertisements are ignored by device id. Scan window 3 s; manual-IP fallback (IP + port) when mDNS finds nothing. macOS: multicast entitlement + `NSBonjourServices` added to the Runner.
- **Port:** `48150` TCP for the pairing/control channel (single constant `bridgeDeskPort`).
- **PIN:** fresh random 6-digit PIN per host session (`Random.secure`, `%06d`); constant-time compare; max **3** wrong attempts per session, then lockout and a fresh PIN is required. The PIN is never logged.
- **TLS:** per-device RSA-2048 key + self-signed certificate generated on first run (via `basic_utils`; Dart has no stdlib X.509 generation), valid 10 years. Stored under app-support `bridgedesk/identity/` (`device_id.txt`, `cert.pem`, `key.pem`); pairings in `bridgedesk/pairings.json`. Trust-on-first-use authenticated by the PIN, then both sides pin the peer's SHA-256 certificate fingerprint; a changed fingerprint on reconnect is rejected with a "fingerprint changed" error. One-way TLS (not mutual TLS): host authenticates the client by PIN, client authenticates the host by PIN + pinned fingerprint.
- **Gotcha found in M1:** `basic_utils` encodes key-usage/extended-key-usage extensions in a form BoringSSL rejects (`CANNOT_PARSE_LEAF_CERT`, while OpenSSL accepts it), so the generated certificate carries no extensions. Harmless here — the cert is pinned by fingerprint, never chain-validated.
- **Transport for M2/M3:** `lib/core/transport/` — length-prefixed JSON control messages (4-byte big-endian length, 16 MiB max, oversized frames rejected) over `SecureSocket`; `SecureChannel.attach()` and `connectPinned()` (fingerprint-checked reconnect) are the reuse points. File payloads will travel chunked, not as single control messages.
- **Tests:** `flutter test` — 30 tests: PIN (format/uniqueness/attempt limit/lockout), framing (round-trip, split chunks, oversized rejection), pairing store (persist/upsert/unpair/corrupt file), identity (stable across restarts, fingerprint format), full TLS handshake on loopback (correct PIN pairs both sides, wrong PIN → lockout, changed cert → refusal, `connectPinned` ok/refusal), plus the M0 widget smoke test.

## Open decisions for user

1. Name (needs: distinct, short, check GitHub/domain).
2. Confirm v1 list above, or swap one item (e.g. file send out, screen view in).
3. Edge direction default + does he have both a Mac and a Windows PC available to test on now?
