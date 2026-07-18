# withoutBG for Mac

A free, private, native macOS app for background removal, powered by **withoutBG Open Weights**. Images are processed locally on your Mac — nothing is uploaded.

The desktop app is the primary product. It includes drag-and-drop processing **and** an optional **Local API** on `http://127.0.0.1:8000` for automation (scripts, GIMP plugin, CI).

> Background removal runs on-device via the bundled **withoutBG Open Weights** Core ML model (`wbgnet_oss`, fp32, v10). A `MockProcessor` is available behind the same `BackgroundRemovalProcessor` protocol for UI development without the model.

## Features

### Desktop

- Drop, open (⌘O), or paste (⌘V) up to **20 images**
- Sequential auto-processing with Quick Look preview
- Responsive thumbnail grid with Photos-style selection
- Export transparent PNGs individually or as a zip
- Light / dark / system appearance
- Finder Services: **Remove Background** on selected images

### Local API (optional)

- Start/stop from the menu bar extra or Settings
- `POST /v1/remove-background` — same inference engine as the desktop
- `GET /health`, `GET /openapi.json`
- Request log and operational metrics in the menu bar
- Loopback-only (`127.0.0.1`) — sandboxed, private

## Downloads

| Product | Audience | Scheme |
|---------|----------|--------|
| **withoutBG** (primary) | Creators + developers | `WithoutBG` |
| **WithoutBG Server** (headless) | CI / automation-only | `WithoutBGServer` |

Most users should install **withoutBG**. The headless server build is for environments that only need the HTTP API.

## Requirements

- macOS 14+
- Xcode 16+ (Swift 5.9+)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build & run

The Xcode project is generated from `project.yml` (gitignored).

```bash
xcodegen generate
open WithoutBG.xcodeproj
```

- **WithoutBG** — windowed desktop app with menu bar Local API controls
- **WithoutBGServer** — menu-bar-only headless distribution (`LSUIElement`)

```bash
# Primary app
xcodebuild -scheme WithoutBG -destination 'platform=macOS' build

# Headless server (advanced)
xcodebuild -scheme WithoutBGServer -destination 'platform=macOS' build
```

Release builds:

```bash
./scripts/release.sh                  # withoutBG DMG (primary)
./scripts/release.sh --server           # WithoutBG Server DMG (headless)
```

## Monorepo layout

```
withoutbg-mac/
├── Packages/WithoutBGCore/     Shared inference, model, settings, product links
├── Apps/
│   ├── WithoutBG/              Primary desktop + embedded Local API
│   └── WithoutBGServer/        Headless menu-bar distribution
├── project.yml
└── scripts/release.sh
```

### Inference

Both the desktop queue and Local API serialize through one `SharedInferenceCoordinator` actor backed by a single `CoreMLProcessor` instance — one model load, fair GPU scheduling.

```
Desktop UI ──┐
             ├── SharedInferenceCoordinator ── CoreMLProcessor ── wbgnet_oss
Local API ───┘
```

Shared code lives in `Packages/WithoutBGCore`. To run the UI without the model, inject `MockProcessor()` at app init.

## Local API quick start

1. Launch **withoutBG**
2. Click the menu bar icon → **Start Local API**
3. Send a request:

```bash
curl -X POST \
  --data-binary @photo.jpg \
  -H "Content-Type: image/jpeg" \
  http://127.0.0.1:8000/v1/remove-background \
  -o result.png
```

OpenAPI spec: `http://127.0.0.1:8000/openapi.json`

## Migration from WithoutBG Server

The standalone [withoutbg-mac-server](https://github.com/withoutbg/withoutbg-mac-server) repository is consolidated into this monorepo. See [docs/MIGRATION.md](docs/MIGRATION.md).

Existing `com.withoutbg.mac.server` installs continue to work via the **WithoutBGServer** target. New users should install **withoutBG** instead.

## License

withoutBG Open Weights — Apache License 2.0. See [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES) for model attributions (DINOv3, Depth Anything V2).
