# BridgeDesk

One mouse and keyboard, shared clipboard (text) and file send between a
Mac and a Windows PC on the same Wi-Fi. No account, no cloud.

Clean-room MVP, built from scratch in Flutter — **not** a fork of
TwinDesk, and it contains no TwinDesk code.

Status: **M1 done.** Real mDNS discovery, 6-digit PIN pairing and a
TLS channel work between two machines on the same Wi-Fi. Mouse/keyboard
sharing is M2, clipboard sync and file transfer are M3 — see
`../MVP_PLAN.md`.

## Download

Ready-to-run builds for Mac and Windows are on the
[Releases page](https://github.com/elsoudy222/BridgeDesk/releases/latest):
`BridgeDesk-macOS.dmg` (or `.zip`) for macOS 13+, and
`BridgeDesk-Windows.zip` for Windows 10/11. The builds are unsigned
for now — see the first-launch notes under "Build installers" below.

Releases are built automatically by GitHub Actions (`.github/workflows/release.yml`)
when a version tag is pushed, e.g. `git tag v0.1.0 && git push origin v0.1.0`.
The Releases page stays empty until the first tag. See the root
[README.md](../README.md) for the full release steps.

> **After cloning:** app icons are binary, so they are not committed.
> Run `python3 tool/generate_icons.py` once (needs Pillow:
> `pip install pillow`) before your first build, or the macOS/Windows
> builds will fail on the missing icon files. The release workflow
> runs this step automatically.

## How pairing works (M1)

1. Start BridgeDesk on **both** computers, on the same Wi-Fi.
2. On the **host** (either computer): open the Pairing tab and tap
   **Show my PIN**. A fresh random 6-digit PIN appears; the app
   listens on TCP port `48150` over TLS.
3. On the **client** (the other computer): open the Devices tab, tap
   **Search**, then tap **Pair** next to the host — or, if discovery
   finds nothing, enter the host's IP + port by hand and tap **Add**,
   then go to the Pairing tab. Enter the PIN and tap
   **Verify PIN & Pair**.
4. On success both computers remember the pairing (Devices shows a
   **Paired** chip; Settings lists the device). Later connections
   reuse the encrypted channel; no PIN needed again.
5. **Unpair** in Settings (per device, or "Unpair all") forgets the
   pairing *and* the pinned certificate — pairing again needs a fresh
   PIN.

If the PIN is wrong 3 times, the host session locks out and the host
must tap **Stop hosting** and **Show my PIN** again for a fresh PIN.
If a paired device's certificate ever changes (e.g. it was
reinstalled), connecting is refused with a "fingerprint changed"
error — unpair and re-pair only if you trust the device.

### Manual-IP fallback

Discovery needs mDNS/Bonjour. If a network blocks multicast, or a
firewall eats it, use **Add by IP** on the Devices tab (or the IP
fields on the Pairing tab) with the other computer's LAN address and
port `48150`. Pairing itself does not need mDNS at all.

## Packages (why each one)

| Package | Why M1 needs it |
| --- | --- |
| `bonsoir` 7.1.6 | mDNS advertise **and** browse on macOS/Windows. `multicast_dns` can only browse — it cannot advertise this device, so it cannot do discovery alone. |
| `basic_utils` 5.8.2 | Pure-Dart generation of the per-device self-signed TLS certificate (RSA 2048). Dart has no stdlib X.509 generation. |
| `crypto` 3.0.8 | SHA-256 fingerprints for certificate pinning. |
| `path_provider` 2.1.6 | App-support directory for the certificate, private key and `pairings.json` on macOS + Windows. |

## Security model (M1)

- Each install generates a stable device id + RSA 2048 key pair + a
  self-signed certificate (10 years), stored under the app-support
  directory in `bridgedesk/identity/` (`device_id.txt`, `cert.pem`,
  `key.pem`). The private key never leaves the device.
- The PIN is never sent in the clear: it travels inside the TLS
  channel. The host's self-signed certificate is trusted on first use
  (TOFU) and authenticated by the PIN; both sides then pin each
  other's SHA-256 certificate fingerprint. A changed fingerprint on
  reconnect is rejected, never silently accepted.
- One-way TLS (not mutual TLS): the host authenticates the client by
  the PIN; the client authenticates the host by the PIN + pinned
  fingerprint. PIN comparison is constant-time; 3 wrong guesses lock
  the session out.
- Known quirk: `basic_utils`' key-usage/extended-key-usage extensions
  are encoded in a form BoringSSL (Dart's TLS stack) rejects with
  `CANNOT_PARSE_LEAF_CERT`, so the generated certificate carries no
  extensions. It is pinned by fingerprint, never chain-validated, so
  the extensions add nothing here.

## Prerequisites

Install the Flutter SDK (stable channel) first. Do **not** build the
macOS or Windows app on a Linux machine — those binaries can only be
built on their own platform.

### Mac

- macOS 13 Ventura or later
- Xcode (from the App Store) + Command Line Tools:
  `xcode-select --install`
- CocoaPods: `sudo gem install cocoapods` (only needed if a plugin
  later requires it; M0 needs none)
- Flutter: download the stable macOS SDK from
  <https://docs.flutter.dev/get-started/install/macos>, unzip it, and
  add its `bin` folder to your `PATH`

### Windows

- Windows 10 or 11 (64-bit)
- Visual Studio 2022 with the **"Desktop development with C++"**
  workload (includes CMake, the Windows 10/11 SDK and MSVC)
- Git for Windows
- Flutter: download the stable Windows SDK from
  <https://docs.flutter.dev/get-started/install/windows>, unzip it,
  and add its `bin` folder to your `PATH`
- Check your setup with `flutter doctor` and fix anything it flags
  for macOS / Windows desktop

## Run it

```sh
cd app
flutter pub get

# On the Mac:
flutter run -d macos

# On Windows:
flutter run -d windows
```

## Build installers (later, once M1–M3 land)

```sh
# On the Mac:
flutter build macos

# On Windows:
flutter build windows
```

The macOS build is unsigned in M0, so the first launch needs
**System Settings › Privacy & Security › Open Anyway** (or
`xattr -dr com.apple.quarantine <path-to-app>`). The Windows build
will trigger SmartScreen — choose **More info › Run anyway**.
Code signing is a later step, not M0.

## Project layout

```
lib/
  main.dart                        App shell + bottom navigation
  core/
    constants.dart                 Service type, port, PIN rules, limits
    storage/app_storage.dart       App-support dir (bridgedesk/)
    identity/device_identity.dart  Device id + self-signed cert + fingerprint
    transport/
      framing.dart                 Length-prefixed JSON control messages
      secure_channel.dart          TLS socket + framed messages
  features/devices/
    devices_screen.dart            Discovered list, manual IP, Pair button
    device_model.dart              PeerDevice model
    discovery_service.dart         Bonsoir mDNS advertise + browse
  features/pairing/
    pairing_screen.dart            Host PIN / enter PIN flow
    pin.dart                       PIN generation + constant-time verify
    pairing_store.dart             pairings.json (remembered pairings)
    pairing_service.dart           PIN handshake + TLS, fingerprint pinning
  features/settings/
    settings_screen.dart           Edge Left/Right, clipboard toggle, unpair
test/
  pin_test.dart                    PIN format, verify, attempt limit
  framing_test.dart                Encode/decode, split chunks, oversize
  pairing_store_test.dart          Persist / reload / unpair
  identity_test.dart               Stable identity, fingerprint format
  pairing_handshake_test.dart      Full TLS pairing on loopback (PIN ok,
                                   wrong PIN lockout, cert-change refusal)
  widget_test.dart                 App shell smoke test
```

## Platform notes (M1)

- **macOS:** the Release build has the multicast entitlement
  (`com.apple.developer.networking.multicast`) plus
  `NSLocalNetworkUsageDescription` / `NSBonjourServices`
  (`_bridgedesk._tcp`) in `Info.plist`. Without them macOS silently
  blocks mDNS. The multicast entitlement needs a signed provisioning
  profile with that capability (Apple approval for App Store
  distribution later), so it is **not** in `DebugProfile.entitlements`:
  an unsigned `flutter run` would fail with "Runner has entitlements
  that require signing with a development certificate." In debug
  builds, discovery on macOS falls back to **Add by IP** (manual IP +
  port `48150`); pairing itself does not need mDNS. If you want mDNS
  discovery in debug too, open `macos/Runner.xcworkspace` in Xcode,
  turn on "Automatically manage signing" with your Apple ID team, and
  add the multicast entitlement back to `DebugProfile.entitlements`.
  First launch still needs Open Anyway for the unsigned build.
- **Windows:** allow BridgeDesk through the firewall on private
  networks when prompted; SmartScreen "Run anyway" for the unsigned
  build.

## Next milestones

- **M2:** mouse/keyboard edge crossing — native Swift (CGEvent) on
  macOS, native C++ (SendInput/hooks) on Windows; needs Accessibility
  + Input Monitoring permission on macOS. Reuses `SecureChannel` +
  `connectPinned()` from M1.
- **M3:** clipboard text sync + file send over the TLS channel
  (framing is ready; file payloads travel chunked, not as one
  control message).
