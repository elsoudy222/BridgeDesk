# BridgeDesk

One mouse and keyboard, shared clipboard (text) and file send between a
Mac and a Windows PC on the same Wi-Fi. No account, no cloud.

Clean-room MVP, built from scratch in Flutter — **not** a fork of
TwinDesk, and it contains no TwinDesk code.

## Download

Get the latest version for your computer from the
[Releases page](https://github.com/elsoudy222/BridgeDesk/releases/latest):

- **macOS** (13 Ventura or later): `BridgeDesk-macOS.dmg` — open it and
  drag BridgeDesk into Applications. (A `.zip` of the `.app` is attached
  next to it if you prefer that.)
- **Windows** (10 / 11, 64-bit): `BridgeDesk-Windows.zip` — unzip it
  anywhere and run `bridgedesk.exe` inside.

Both computers must be on the same Wi-Fi. On first run, allow the
macOS Local Network prompt, and allow BridgeDesk through the Windows
firewall on private networks.

> The builds are **unsigned** for now, so the OS will ask once before
> opening them: on macOS use **System Settings › Privacy & Security ›
> Open Anyway** (or `xattr -dr com.apple.quarantine
> /Applications/BridgeDesk.app`); on Windows choose **More info › Run
> anyway** on the SmartScreen prompt. Code signing is a later step.

No release is published yet? The Releases page is empty until the
first version tag is pushed — see "Cutting a release" below.

## What it does (status: M1 done)

- **Discovery:** each computer finds the other on the same Wi-Fi
  (mDNS `_bridgedesk._tcp`), with manual IP entry as a fallback.
- **Pairing:** a fresh random 6-digit PIN per session; 3 wrong guesses
  lock the session out. Pairings are remembered across restarts.
- **Encrypted channel:** per-device self-signed certificate, PIN
  travels only inside TLS, and each side pins the other's certificate
  fingerprint — a changed fingerprint is refused, never silently
  accepted.
- **Coming next:** M2 mouse/keyboard sharing across the screen edge,
  M3 clipboard sync + file send.

Full plan: [MVP_PLAN.md](MVP_PLAN.md). Developer setup and pairing
steps: [app/README.md](app/README.md).

## Cutting a release

Releases are built automatically by GitHub Actions on macOS and
Windows runners (binaries can only be built on their own platform):

```sh
git tag v0.1.0
git push origin v0.1.0
```

Watch the Actions tab; when both jobs finish, the `.dmg`, macOS
`.zip` and Windows `.zip` are attached to the
[release for that tag](https://github.com/elsoudy222/BridgeDesk/releases).
You can also run the workflow by hand from the Actions tab — that
uploads the builds as artifacts only, without creating a Release.

## Building from source

```sh
git clone https://github.com/elsoudy222/BridgeDesk.git
cd BridgeDesk/app
python3 tool/generate_icons.py   # once: app icons are generated, not committed
flutter pub get
flutter run -d macos    # on a Mac
flutter run -d windows  # on Windows
```
