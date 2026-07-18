# Migration: withoutbg-mac-server → withoutbg-mac

The Local API server has been merged into the **withoutBG** desktop application. Both products now share one inference engine, one Core ML model, and one settings schema.

## What changed

| Before | After |
|--------|-------|
| Two separate apps | One primary app (`withoutBG`) + optional headless build |
| Two model copies in memory if both ran | Single `SharedInferenceCoordinator` |
| `withoutbg-mac-server` repo | `Apps/WithoutBGServer/` in [withoutbg-mac](https://github.com/withoutbg/withoutbg-mac) |
| Menu-bar-only server | Desktop app + menu bar Local API controls |

## For most users

**Install withoutBG** from the primary DMG. Enable the Local API from:

- Menu bar → **Start Local API**
- Settings → **Local API**
- Empty state → **Start Local API** promo

Bundle ID: `com.withoutbg.mac`

## For automation / CI users

The **WithoutBG Server** headless build remains available for environments that only need the HTTP API:

- Scheme: `WithoutBGServer`
- Bundle ID: `com.withoutbg.mac.server` (unchanged for plugin compatibility)
- CLI: `./WithoutBG\ Server.app/Contents/MacOS/WithoutBG\ Server --port 8000 --start`

Most users should migrate to the unified desktop app when convenient.

## Settings migration

Legacy UserDefaults keys are migrated automatically:

| Legacy key | Unified key |
|------------|-------------|
| `serverPort` | `localAPIPort` |
| `startOnLaunch` | `localAPIStartOnLaunch` |

## API compatibility

Endpoints are unchanged:

- `GET /health`
- `GET /openapi.json` (new)
- `POST /v1/remove-background`

Port default remains **8000**. Loopback binding (`127.0.0.1`) unchanged.

## Repository status

The `withoutbg-mac-server` repository is archived. All development continues in `withoutbg-mac`.
