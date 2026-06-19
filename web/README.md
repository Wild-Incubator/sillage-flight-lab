# Sillage

Rails/Hotwire logbook for FlySight sessions.

## Stack

- Rails 8
- Turbo + Stimulus
- SQLite
- Active Storage
- Three.js and Chart.js loaded in the browser for jump analysis

## Identity

The app uses the dedicated Sillage design system: a compact avionics-inspired identity for FlySight trajectory analysis. See `docs/design-system.md`.

## Run

```sh
bundle install
bin/rails db:prepare
bin/rails server
```

Open `http://localhost:3000`.

## Import

The MVP accepts:

- a ZIP containing one FlySight 2 session folder with `TRACK.CSV` and `SENSOR.CSV`
- `TRACK.CSV` and `SENSOR.CSV` uploaded together
- a FlySight V1 CSV file

FlySight 2 sensor rows are stored with their raw readings and synchronized to GPS time when `$TIME` rows are present.

## Cesium photorealistic 3D

Set a browser-safe Cesium ion token to enable Google Photorealistic 3D Tiles in the jump detail scene:

```sh
CESIUM_ION_TOKEN=your_public_ion_token bin/rails server
```

The token must have Cesium ion permissions for Google Photorealistic 3D Tiles. Without it, the app keeps the lightweight local 3D fallback.

## Tests

```sh
bin/rails test
```

Synthetic FlySight fixtures live in `test/fixtures/files`; real device exports should stay out of versioned fixtures unless anonymized.
