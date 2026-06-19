# Sillage

Sillage is the software workspace for the Exowing project: a complete flight
system for a personal rigid wing, covering flight preparation, live in-flight
support, replay, analysis, and maintenance.

The repository currently contains a Rails application in `web/` and a `docs/`
folder with project, contract, pricing, roadmap, and HUD/FDR requirements
documents. This README summarizes those documents so the team has a shared
project overview.

## Product Vision

The project targets a personal rigid-wing system developed in stages:

- **GLD / Glider Wing System**: an unpowered rigid wing used to validate
  aerodynamics, structure, safety, human factors, parachute integration,
  sensors, communications, and the FDR.
- **EPW / Electric-Powered Wings System**: the powered evolution with electric
  propulsion, batteries, power chain, enriched HUD/FDR, and ground station.
- **JPW / Jet-Powered Wing**: a potential roadmap extension using jet propulsion
  and an architecture derived from EPW/JPW work.

The functional ambition covers:

- pre-flight preparation, checklists, mission configuration, and startup checks;
- live pilot assistance through HUD, audio, FDR, localization, and telemetry;
- air-to-air and air-to-ground communication;
- complete flight data recording;
- post-flight analysis with maps, charts, 3D/KMZ replay, and flight comparison;
- pilot logbook, maintenance tracking, spare parts, cycles, and anomalies.

## Product Naming and Architecture

The software suite should be named **Sillage**, not "Exopter Server". Exopter
names the company, vehicle, and program; Sillage names the operating software
suite that prepares, supports, records, analyzes, and improves the Exopter
flight program. The internal framing can be: **Sillage is the Exopter operating
suite**.

Sillage should be treated as one coherent product family rather than a generic
cloud back office. The suite can expose distinct surfaces as the program grows:

- **Sillage Flight**: pre-flight preparation, flight support, post-flight
  analysis, replay, logbook, HUD/FDR support, and maintenance workflows.
- **Sillage Forge**: AI tooling, agent workflows, OpenProject integration,
  engineering support, documentation, and backlog execution.
- **Sillage Core**: authentication, authorization, audit trails, storage,
  integrations, administration, deployment, and shared operational services.

Future surfaces can use the same short, evocative naming system:

- **Sillage Atlas**: maps, terrain, replay, route comparison, airspace context,
  and geospatial analysis.
- **Sillage Hangar**: fleet, wing hardware, equipment, maintenance, spare parts,
  cycles, anomalies, and readiness state.
- **Sillage Signal**: telemetry, live feeds, sensor streams, communications,
  alerts, and operational monitoring.

The preferred technical shape is a modular monolith first: one deployable
platform, with clear domains, namespaces, permissions, audit boundaries, and
data ownership. Split into separate deployable applications only when a real
constraint justifies it, such as different deployment cadence, safety or
security isolation, regulatory pressure, scaling needs, or separate operational
ownership.

Sillage should be one house with several rooms: not a shapeless mega-app, not a
premature city of services. It should become the inspiring place where the
Exopter program is operated.

## Reference Data

The contract specifications describe two primary levels.

### GLD

- 1 pilot, target pilot mass 90 kg, range 80 to 95 kg.
- Target maximum takeoff mass: 140 kg excluding payload.
- Target empty mass: 45 kg maximum.
- Horizontal distance: more than 10 km from an exit altitude of 5000 m or less,
  with parachute opening sequence at 1500 m.
- Optimal speed: 170 to 230 km/h.
- Desired payload: up to 30 kg, with demonstration potentially excluding payload
  for safety reasons.
- Operational wingspan: 2.5 m maximum.
- Launch platform: Airbus AS350 or equivalent.

### EPW

- 1 pilot, same pilot range as GLD.
- Target maximum takeoff mass: 203 kg excluding payload.
- Target empty mass: 108 kg maximum.
- Horizontal distance: more than 25 km from an exit altitude of 5000 m or less,
  with parachute opening sequence at 1500 m.
- Optimal speed: 170 to 230 km/h.
- Electric propulsion integrated into the GLD architecture.
- Desired line-of-sight ground station link at at least 5 km.

The wings must be inherently stable or stability-augmented. Parachute and helmet
equipment must be certified or safe for the intended use.

## Embedded System

The embedded scope from the HUD/FDR requirements includes the following blocks.

### HUD

- Readable display facing the sun and non-blinding in low-light conditions.
- Manual or automatic brightness adjustment.
- Safe failure mode with black screen instead of white screen or blinding color.
- Emergency shutdown button or control, with a long action planned around 5 s.
- Main neon-green color, with orange, red, and grey to distinguish critical
  information.
- Quickly switchable GLD, EDF, and JET display modes.
- Stereoscopic far-field display to reduce focus effort.
- Integration into a Tonfly TFX helmet.
- Compatibility with humidity, condensation, visor use, and polarization.
- Basic configuration editable by the Exopter team in less than 24 h.
- Deeper configuration editable by the supplier within a few weeks.

Planned display information includes airspeed, AGL/AMSL altitude, distance to
destination, glide ratio, heading, waypoint, separation from other pilots, fault
alerts, temperature, power, autonomy, and system state.

### FDR and Sensors

The FDR must record flight data locally and allow upload to the Exopter server.
Expected exports include CSV, charts, KMZ, and direct integration into an
application with maps.

Sensors and modules mentioned in the documents:

- gyroscope, accelerometer, and magnetometer;
- GNSS/GPS, including the need to manage acquisition inside the aircraft;
- static pressure, Kiel/Pitot probe, and airspeed;
- system and battery temperature;
- ESP32-type module for prototype work;
- NiMH battery, status LED, remote switch;
- camera and T0 synchronization at aircraft exit.

Planned placement:

- on the wing: Pitot/pressure, GPS, and camera;
- on the seat: attitude, GPS, and VHF;
- on the helmet: GPS, intercom, and camera.

### Live Functions

- Waypoint navigation with adjustable virtual cylinder.
- Terrain alert along the trajectory, based on WGS84 topography or equivalent.
- Warning when a sensor or parameter becomes erratic.
- Audible altimeter correlated with the display as redundancy.
- Independent pilot and wing localization, switchable on/off.
- Pilot intercom and VHF air-to-air / air-to-ground communication.
- Optional live feed for flight information and camera.
- Built-In Test Equipment, watchdog, startup tests, and on-demand tests.

## Ground and Cloud Application

The `web/` application is the current software state. It currently acts as the
Sillage Flight Lab base for importing and analyzing FlySight sessions.

Current stack:

- Rails 8;
- Hotwire, Turbo, and Stimulus;
- SQLite;
- Active Storage;
- Solid Queue;
- Three.js and Chart.js in the browser;
- FlySight V1 and FlySight 2 import;
- storage for `flight_imports`, `jumps`, `track_points`, and `sensor_samples`.

Existing or target-aligned features:

- upload of FlySight 2 ZIP files containing `TRACK.CSV` and `SENSOR.CSV`;
- direct upload of `TRACK.CSV` + `SENSOR.CSV`;
- FlySight V1 CSV import;
- sensor data synchronization to GPS time when `$TIME` rows are present;
- trajectory visualization and jump metrics;
- natural base for post-flight replay, logbook, maintenance, and FDR analysis.

## Run The Web Application

```sh
cd web
bundle install
bin/rails db:prepare
bin/rails server
```

Then open `http://localhost:3000`.

Tests:

```sh
cd web
bin/rails test
```

## Deployment

The web project is already prepared for Kamal.

Important files:

- `web/config/deploy.yml`
- `web/bin/kamal`
- `web/.env.deploy.local.example`
- `web/docs/deploiement-kamal.md`

The `web/.env.deploy.local` file is intentionally local and can be loaded by:

- `bin/kamal`, through the Ruby wrapper;
- `bundle exec kamal`, through the ERB loader in `config/deploy.yml`;
- global Kamal launched from `web/`, for the same reason.

Create the local deployment environment:

```sh
cd web
cp .env.deploy.local.example .env.deploy.local
```

Planned variables:

- `RAILS_MASTER_KEY`
- `KAMAL_REGISTRY_PASSWORD`
- `CESIUM_ION_TOKEN`
- `BACKUPS_ENABLED`
- `MONITORING_ENABLED`

The documented target is currently `sillage.wild.eu` on a single VPS with
Docker, HTTPS through `kamal-proxy`, a local private registry, and persistent
storage in `/rails/storage`.

## Milestones and Budget

The pricing documents contain several views that are not strictly identical:
detailed quote, options, short version, and internal roadmap. The main orders of
magnitude are:

- detailed GLD + EPW + training quote: about **2,998,844**;
- Phase 1 + training: about **2,212,259**;
- Phase 2: about **786,585**;
- short internal roadmap: total around **493,500** before JPW extension;
- FDR: commercial line around **41,350** in the quote, with a much lower
  prototype assumption in the short roadmap;
- options: extra training, GLD/EPW certification, GLD/EPW series production,
  helmet display, payload, landing assistance system, spare parts, maintenance,
  and shipping.

Contract milestones from the scope:

- **T0+3**: GLD design and analyses, EPW progress update.
- **T0+6**: GLD#1 fabrication/assembly, first tunnel results, first data
  gathering.
- **T0+9**: GLD#1 test results, GLD#2 fabrication.
- **T0+12**: GLD results and EPW design/analysis.
- **T0+18**: EPW tunnel results, second data gathering, and training.
- **T0+24**: EPW demonstration, 2 GLD prototypes and 1 EPW prototype completed.

## Source Documents

The `docs/` folder contains:

- `Draft specs to Contractor on EPW prototype v4 2026 02 03.docx`:
  EPW prototype scope of work, GLD/EPW phases, specifications, deliverables,
  schedule, and payment.
- `EXO - DEV - HUD & FDR requirements - V0.1 - 26JAN2026 - BLD.xlsx`:
  HUD/FDR requirements, display, sensors, live functions, hardware placement,
  and prototype notes.
- `ORG_MNG_roadmap short_V0.1_20260526_CTS.xlsx`:
  short roadmap, internal costs, GLD/EPW/JPW sequence, and operational notes.
- `ORG - ACC - CUS - QTN - Short Draft Singapore pricing GLD   EDF - V0.5 - 09FEB2026 - BLD.xlsx`:
  commercial summary by phase, milestone, and total.
- `ORG - ACC - CUS - QTN - Draft Singapore pricing GLD   EDF - V4 - 09FEB2026 - BLD.xlsx`:
  detailed GLD/EPW quote with line items, providers, quantities, and milestones.
- `ORG - ACC - CUS - QTN - Draft Singapore pricing OPTIONS GLD   EDF - V0.1 - 09FEB2026 - BLD.xlsx`:
  training, certification, series production, HUD, payload, spare parts,
  maintenance, and shipping options.
- `Updated COC_20 Jan 2026 - cleaned commentaires MPO.docx`:
  contract conditions: payment, rejection/acceptance, confidentiality, security,
  export, IP, warranty, supply-chain traceability, risk management, design
  adequacy, integration/interoperability, and Singapore law.

## Open Points

- Define the actual criticality level of each function: FDR, HUD, alerts, motor,
  audio, telemetry, and cloud.
- Decide what is advisory only and what can directly influence flight safety.
- Choose the FDR strategy: lightweight prototype recorder or hardened recorder
  with aviation-like requirements.
- Specify data formats, timestamping, camera synchronization, and upload
  pipeline.
- Define cybersecurity, confidentiality, and data-retention rules before any
  sensitive testing.
- Clarify the differences between the internal roadmap, short quote, detailed
  quote, and options.
- Convert HUD/FDR requirements into a testable backlog with acceptance criteria,
  HIL bench tests, and degradation scenarios.
