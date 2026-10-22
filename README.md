# Kyōmei (共鳴)

**Your sound. In harmony.** A native macOS app for Soundcore earbuds and headphones: noise
cancelling, equalizer, touch controls and battery from your menu bar, with a desktop widget. No
phone in between. By [Kakushin](https://kakushin.dev). Website: <https://kyomei.kakushin.dev>.

> Kyōmei is an independent open-source project. It is not affiliated with, endorsed or sponsored
> by Anker Innovations or Soundcore. Soundcore is a trademark of its owner.

## Requirements

| | |
| --- | --- |
| **macOS** | **14 Sonoma or later** (`LSMinimumSystemVersion` 14.0) |
| **Mac** | Apple silicon or Intel (universal binary) |
| **Bluetooth** | The Soundcore device paired in System Settings → Bluetooth |
| **Desktop widget** | macOS 14 or later (desktop or Notification Center) |
| **Liquid Glass look** | macOS 26 or later; macOS 14 and 15 use translucent materials |

Tested on real hardware: macOS 27 with a soundcore R60i NC (firmware 03.89). Other models are
checked against recorded packets only; see the table below.

### Building from source

- macOS with the **macOS 26 SDK or newer**: Xcode 26+, or the Command Line Tools with that SDK
  (the code uses Liquid Glass APIs behind `#available`, so it still runs on macOS 14)
- Swift 6 (ships with the toolchain above)
- For the website: Node.js 22.23.4+ (CI uses Node 24) or Docker

## Install

1. Download `Kyomei-X.Y.Z-macOS.dmg` from [Releases](https://github.com/kakushindev/kyomei-core/releases).
   Check it: `shasum -a 256 -c Kyomei-X.Y.Z-macOS.dmg.sha256`.
2. Open the disk image and drag **Kyomei** to Applications.
3. Open Kyōmei. If a release is not notarized, macOS stops the first launch: open
   **System Settings → Privacy & Security** and choose **Open Anyway** for Kyōmei. That allows
   this one app; there is no need to turn Gatekeeper off.
4. Allow Bluetooth access when asked.

### Desktop widget

Right-click the wallpaper → **Edit Widgets** → search **Kyōmei** → add the small size (battery
rings) or the medium size (battery plus one-click sound mode buttons). The widget reads the
state the app last saw, so keep Kyōmei running (menu bar only is fine). Mode buttons switch the
mode without bringing the app forward. If the widget does not appear in the gallery, open the app
once from /Applications and log out and back in.

## Supported models

| Model | Code | Status |
| ----- | ---- | ------ |
| soundcore R60i NC | D1202C | Tested on hardware (firmware 03.89) |
| soundcore P31i | D1202 | Same layout as R60i NC; not yet tested on hardware |
| soundcore Liberty 4 NC | A3947 | Checked against recorded packets |
| soundcore Liberty 5 | A3957 | Checked against recorded packets |
| soundcore P40i | A3955 | Checked against recorded packets |
| soundcore P30i / R50i NC | A3959 | Checked against recorded packets |
| soundcore P20i / R50i / P25i | A3949 | Checked against recorded packets |
| soundcore Space Q45 | A3040 | Checked against recorded packets |
| soundcore Space One | A3035 | Checked against recorded packets |
| Soundcore Life Q30 | A3028 | Checked against recorded packets |
| Soundcore Life Q35 | A3027 | Implemented; no recordings yet |
| soundcore Space A40 | A3936 | Implemented; no recordings yet |
| soundcore Q20i | A3004 | Implemented; no recordings yet |

The model is detected from the Bluetooth name, then confirmed by parsing the device's state
packet; **Device → Model** overrides it per device. If your model works (or doesn't), please
[open an issue](https://github.com/kakushindev/kyomei-core/issues).

## Features

- Overview with a live resonance animation of the current mode, battery for each bud and the case
- Sound modes per model: adaptive / manual / scene ANC, wind noise reduction, transparency
- 8-band equalizer with live curve, the model's presets and saved custom profiles
- Touch control remapping, restore defaults
- Spatial audio, multipoint device list, LDAC and the other settings a model exposes
- Switch between all paired Soundcore devices; auto connect on launch, Bluetooth connect, wake
- Menu bar panel, desktop widget, low-battery notifications, open at login, optional Dock icon,
  appearance (system / light / dark), ⌘1 ⌘2 ⌘3 for modes, ⌘M to cycle, ⌘R to refresh

## Build

```bash
swift test                            # protocol tests
./scripts/build-app.sh                # → build/Kyomei.app (universal, ad-hoc signed, with widget)
./scripts/build-app.sh --install      # → /Applications/Kyomei.app
./scripts/verify-app.sh build/Kyomei.app
./scripts/package-dmg.sh build/Kyomei.app dist   # → dist/Kyomei-X.Y.Z-macOS.dmg + .sha256
```

With only the Command Line Tools, `swift test` needs the Testing plugin path:
`swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`.

The app must run as a bundle (not the bare binary) so macOS attributes the Bluetooth permission
to it. Debug builds can render every screen offscreen without a device:
`SOUNDCORE_SNAPSHOT=/tmp/shots .build/debug/SoundcoreMac`.

## Releases

Push a tag `vX.Y.Z` matching the `VERSION` file. `.github/workflows/release.yml` tests, builds,
signs and notarizes when the signing secrets are configured, packages the DMG, verifies it,
writes release notes and publishes the GitHub Release. Without signing secrets the release is
built ad-hoc signed and its notes say so. Nothing is published from pull requests.

Signing secrets (optional): `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`,
variable `MACOS_SIGNING_IDENTITY`; notarization: `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`.
Never commit certificates.

## Website

`website/` is the landing page (Astro + TypeScript + Tailwind). The download button reads the
latest stable release from the public GitHub API at runtime.

```bash
cd website && npm ci && npm run dev         # http://localhost:4321
cd website && npm run verify                # lint, type-check, tests, build, dist checks
cd website && docker compose up -d --build  # nginx container on 127.0.0.1:8080
```

The container runs unprivileged nginx with a strict Content-Security-Policy and a read-only
filesystem. Point the existing Cloudflare Tunnel at `http://127.0.0.1:8080`; see
`deploy/cloudflared/config.example.yml`. Check a running container with
`website/scripts/smoke-test.sh http://127.0.0.1:8080`. Step-by-step VPS guide (Docker, host nginx,
Cloudflare Tunnel): [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

## How it works

The iOS app is FairPlay encrypted, so the protocol comes from the open-source
[OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30) device implementations, ported to Swift and
checked against a real R60i NC and against OpenSCQ30's own device tests
(`Tests/SoundcoreKitTests/OpenSCQ30Fixtures.swift`, generated): 225 of 230 expected setting
values and every expected outbound packet match.

Frames are `08 ee 00 00 00 | cmd(2) | len u16 LE | body | sum8` outbound and
`09 ff 00 00 01 …` inbound, over the vendor RFCOMM service found by SDP.

- `Sources/SoundcoreKit`: framing, structures, per-model profiles and parsers, sound-mode codecs,
  equalizer writers, button logic, widget snapshot, brand constants
- `Sources/SoundcoreMac`: Bluetooth (SDP, paging, RFCOMM), `DeviceController`, UI
- `Sources/SoundcoreWidget`: WidgetKit extension (sandboxed; reads
  `~/Library/Application Support/Kyomei/widget.json`, switches modes via `kyomei://`)

## License

[GPL-3.0-or-later](LICENSE). Model tables and test fixtures are derived from OpenSCQ30, which is
GPL-3.0-or-later.
