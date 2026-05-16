# Sillage Design System

Sillage is a compact flight-analysis identity for FlySight logs. It should feel like an avionics workbench: precise, quiet, and technical, with enough signal color to make trajectory events easy to scan.

## Identity

- Name: Sillage
- Tagline: Flight Lab
- Mark: a dark instrument tile crossed by a coral-to-aqua trajectory, with a lime axis and amber event point.
- Tone: concise operational French/English. Prefer action verbs like "charger", "importer", "analyser", "ajuster".

## Tokens

CSS tokens live in `app/assets/stylesheets/application.css` and use the `--ds-*` prefix.

- Base: `--ds-bg`, `--ds-panel`, `--ds-ink`, `--ds-muted`, `--ds-line`
- Instrument: `--ds-night`, `--ds-night-2`
- Signal colors: `--ds-teal`, `--ds-aqua`, `--ds-coral`, `--ds-amber`, `--ds-violet`, `--ds-lime`
- Shape: 8px radius for app surfaces and controls
- Type: stable rem sizes with mobile overrides; no viewport-scaled text

## Components

- App header: brand mark, product name, tagline, primary navigation, language switch.
- Page heading: eyebrow with trajectory rule and a direct page action.
- Tool panel: framed operational surface for forms, metadata and analysis controls.
- Stats panel and metric strip: dense numeric summaries with muted labels and strong values.
- Upload dropzone: instrument-style panel with dashed boundary and subtle trajectory color.
- Jump card and import row: repeated items only; hover lifts slightly and reveals aqua accent.
- Trajectory surface: full-width dark instrument band with Three.js canvas and scrubber.

## Usage

Keep layouts data-first. Avoid marketing composition, decorative hero art, and nested cards. Use signal colors for state and trajectory, not for large background domination. The UI should always make the next operational action obvious.
