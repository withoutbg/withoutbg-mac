# withoutBG for Mac

A free, private, native macOS app for background removal, powered by **withoutBG Open Weights**. Images are processed locally on your Mac — nothing is uploaded.

> Background removal runs on-device via the bundled **withoutBG Open Weights** Core ML model (`wbgnet_oss_fp32.mlpackage`, fp32, CPU + GPU). A `MockProcessor` is still available behind the same `BackgroundRemovalProcessor` protocol for running the UI without the model.

## Features

- Drop, open (⌘O), or paste (⌘V) up to **20 images**
- Sequential auto-processing with animated phase previews (scan line, edge glow, mask reveal)
- Responsive thumbnail grid with Photos-style selection
- Quick Look-style image preview with Space and arrow-key navigation
- Right-click context menu actions for preview, download, copy, rename, and delete
- Background picker: transparent / white / black, export as PNG
- **Export All** to a `withoutbg-results.zip`
- Light / dark / system appearance
- Full keyboard + reduced-motion support

## Requirements

- macOS 14+
- Xcode 16+ (Swift 5.9+)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build & run

The Xcode project is generated from `project.yml` (it is gitignored).

```bash
xcodegen generate
open WithoutBG.xcodeproj
```

In Xcode, select the **WithoutBG** scheme and press **Run** (⌘R).

If Run fails with a missing `WithoutBGQuickAction` file, the `.xcodeproj` is out of date — regenerate it:

```bash
xcodegen generate
```

Then quit and reopen the project in Xcode.

## Architecture

```
WithoutBG/
├── App/        WithoutBGApp (@main), AppCommands, AppModel
├── Models/     Job, JobStatus, ProcessingPhase, ProcessorResult
├── Services/   BackgroundRemovalProcessor (protocol), MockProcessor,
│               CoreMLProcessor, ProcessingQueue, ImageUtilities,
│               ImageIngestion, ExportService, ProductLinks, AppSettings
├── Views/      ContentView, DropZoneView, BatchToolbarView, QueueGridView,
│               ImageCardView, ImagePreviewOverlay, ProcessingPreviewView,
│               SettingsView, AboutView
├── Design/     WBGColors, CheckerboardBackground, WBGAnimations
└── Resources/  Assets.xcassets, product-links.json
```

### Inference

`ProcessingQueue` depends only on the `BackgroundRemovalProcessor` protocol.
The shipping processor is `CoreMLProcessor`, which:

1. Letterboxes the prepared image onto a 1024×1024 black canvas (top-left).
2. Wraps it in a 1024×1024 RGB `CVPixelBuffer` (the model normalizes uint8 → `[0, 1]` internally).
3. Runs the bundled `wbgnet_oss_fp32` model (`MLModelConfiguration.computeUnits = .cpuAndGPU`).
4. Crops the `(1, 1, 1024, 1024)` alpha to the valid region and resizes it back
   to the source dimensions, then composites the cutout.

To run the UI without the model, swap one line in `WithoutBGApp.swift`:
`AppModel(processor: MockProcessor())`. No views change.

> The `.mlpackage` (~540 MB) lives at `WithoutBG/Resources/wbgnet_oss_fp32.mlpackage`
> and is compiled to `.mlmodelc` at build time. It is **not** git-ignored, so
> consider Git LFS (or excluding it) before committing.
