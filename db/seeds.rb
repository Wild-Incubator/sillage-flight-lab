# This file should ensure the existence of records required to run the application in every environment.
# Development gets readable synthetic flights for validating terrain, charts, and event markers.

BRENTO_POINT_ROWS = [
  [ 0, 45.99385, 10.90442, 1475.0 ],
  [ 3, 45.99380, 10.90520, 1448.0 ],
  [ 7, 45.99374, 10.90665, 1392.0 ],
  [ 12, 45.99366, 10.90870, 1315.0 ],
  [ 18, 45.99358, 10.91125, 1215.0 ],
  [ 25, 45.99355, 10.91430, 1100.0 ],
  [ 33, 45.99362, 10.91765, 965.0 ],
  [ 42, 45.99382, 10.92115, 820.0 ],
  [ 52, 45.99418, 10.92445, 660.0 ],
  [ 62, 45.99478, 10.92720, 520.0 ],
  [ 70, 45.99520, 10.92820, 440.0 ],
  [ 86, 45.99620, 10.92800, 360.0 ],
  [ 106, 45.99685, 10.92685, 305.0 ],
  [ 126, 45.99640, 10.92580, 260.0 ],
  [ 145, 45.99565, 10.92618, 225.0 ]
].freeze

GAP_TALLARD_POINT_ROWS = [
  [ 0, 44.51150, 5.94200, 4200.0 ],
  [ 8, 44.50980, 5.95200, 4090.0 ],
  [ 16, 44.50700, 5.96500, 3920.0 ],
  [ 25, 44.50320, 5.97950, 3710.0 ],
  [ 35, 44.49790, 5.99350, 3460.0 ],
  [ 45, 44.49200, 6.00600, 3200.0 ],
  [ 58, 44.48560, 6.01700, 2910.0 ],
  [ 72, 44.47900, 6.02600, 2620.0 ],
  [ 88, 44.47280, 6.03200, 2320.0 ],
  [ 105, 44.46750, 6.03550, 2010.0 ],
  [ 122, 44.46300, 6.03700, 1690.0 ],
  [ 138, 44.45980, 6.03780, 1390.0 ],
  [ 154, 44.45620, 6.04060, 1160.0 ],
  [ 175, 44.45200, 6.04240, 925.0 ],
  [ 200, 44.44980, 6.03920, 740.0 ],
  [ 225, 44.45040, 6.03500, 650.0 ],
  [ 250, 44.45270, 6.03640, 610.0 ],
  [ 272, 44.45500, 6.03780, 596.0 ]
].freeze

DEMO_FLIGHTS = [
  {
    session_id: "demo-monte-brento",
    source_filename: "demo_monte_brento_tracksuit.csv",
    start_time: Time.utc(2024, 4, 20, 6, 10, 0),
    point_rows: BRENTO_POINT_ROWS,
    opening_elapsed: 62,
    landing_elapsed: 145,
    name: "Monte Brento - tracksuit Sarca",
    location: "Monte Brento, Dro, Trentino, Italie",
    notes: "Demo synthetic tracksuit flight from the Becco dell'Aquila exit, with a long push away from the wall before canopy flight.",
    details: {
      "format" => "synthetic_brento_tracksuit_demo",
      "source" => "Monte Brento / Becco dell'Aquila / tracksuit Sarca valley demo",
      "discipline" => "tracksuit BASE",
      "exit_reference" => "45.9938527, 10.9044185",
      "landing_reference" => "45.995653, 10.926176"
    },
    satellite_count: 17,
    vbat_drop_per_second: 0.0018
  },
  {
    session_id: "demo-gap-tallard-wingsuit",
    source_filename: "demo_gap_tallard_wingsuit.csv",
    start_time: Time.utc(2024, 6, 15, 9, 20, 0),
    point_rows: GAP_TALLARD_POINT_ROWS,
    opening_elapsed: 138,
    landing_elapsed: 272,
    name: "Gap Tallard - wingsuit avion",
    location: "Aerodrome de Gap Tallard LFNA, Hautes-Alpes, France",
    notes: "Demo synthetic wingsuit flight from an aircraft drop, with canopy approach and landing on Gap Tallard aerodrome.",
    details: {
      "format" => "synthetic_gap_tallard_wingsuit_demo",
      "source" => "Gap Tallard LFNA aircraft wingsuit demo",
      "drop_reference" => "44.511500, 5.942000",
      "landing_reference" => "44.455000, 6.037800",
      "runway_reference" => "LFNA main runway 02/20, QFU 024/204"
    },
    satellite_count: 19,
    vbat_drop_per_second: 0.0011
  }
].freeze

def track_points_from_rows(rows, start_time, satellite_count:)
  rows.each_with_index.map do |(elapsed, lat, lon, altitude), index|
    previous = rows[[ index - 1, 0 ].max]
    next_row = rows[[ index + 1, rows.size - 1 ].min]
    dt = [ next_row[0] - previous[0], 1 ].max
    mean_lat = lat * Math::PI / 180.0
    vel_n = ((next_row[1] - previous[1]) * 111_320.0) / dt
    vel_e = ((next_row[2] - previous[2]) * Math.cos(mean_lat) * 111_320.0) / dt
    vel_d = ((previous[3] - next_row[3]) / dt).clamp(0.2, 48.0)
    heading_deg = Math.atan2(vel_e, vel_n) * 180.0 / Math::PI
    heading_deg += 360.0 if heading_deg.negative?

    {
      recorded_at: start_time + elapsed,
      lat: lat,
      lon: lon,
      altitude_m: altitude,
      vel_n_mps: vel_n,
      vel_e_mps: vel_e,
      vel_d_mps: vel_d,
      heading_deg: heading_deg,
      horizontal_accuracy_m: 1.0,
      vertical_accuracy_m: 1.5,
      speed_accuracy_mps: 0.4,
      satellite_count: satellite_count,
      gps_fix: 3
    }
  end
end

def sensor_samples_from_rows(rows, start_time, opening_elapsed:, vbat_drop_per_second:)
  rows.flat_map do |elapsed, _lat, _lon, altitude|
    pressure = 101_325.0 * (1.0 - (2.25577e-5 * altitude))**5.25588
    temperature = 19.0 - ((altitude - 600.0) * 0.0065)
    vertical_load = elapsed < opening_elapsed ? 1.08 + (Math.sin(elapsed / 13.0) * 0.12) : 0.78

    [
      {
        sensor_type: "BARO",
        recorded_at: start_time + elapsed,
        elapsed_seconds: elapsed,
        readings: { "pressure" => pressure.round(1), "temperature" => temperature.round(2) }
      },
      {
        sensor_type: "IMU",
        recorded_at: start_time + elapsed,
        elapsed_seconds: elapsed,
        readings: {
          "wx" => (Math.sin(elapsed / 7.0) * 8.0).round(3),
          "wy" => (Math.cos(elapsed / 9.0) * 6.0).round(3),
          "wz" => (Math.sin(elapsed / 5.0) * 10.0).round(3),
          "ax" => (Math.sin(elapsed / 6.0) * 0.08).round(3),
          "ay" => (Math.cos(elapsed / 8.0) * 0.1).round(3),
          "az" => vertical_load.round(3),
          "temperature" => temperature.round(2)
        }
      },
      {
        sensor_type: "VBAT",
        recorded_at: start_time + elapsed,
        elapsed_seconds: elapsed,
        readings: { "voltage" => (4.12 - elapsed * vbat_drop_per_second).round(3) }
      }
    ]
  end
end

def seed_synthetic_flight(config)
  start_time = config.fetch(:start_time)
  flight_import = FlightImport.find_or_initialize_by(session_id: config.fetch(:session_id))
  flight_import.assign_attributes(
    source_filename: config.fetch(:source_filename),
    status: "imported",
    device_id: "Sillage demo",
    firmware_version: "demo",
    log_started_at: start_time,
    details: config.fetch(:details)
  )
  flight_import.save!

  raw_points = track_points_from_rows(
    config.fetch(:point_rows),
    start_time,
    satellite_count: config.fetch(:satellite_count)
  )
  metrics = Jumps::TrackMetrics.new(raw_points)
  points = metrics.prepared_points
  sensors = sensor_samples_from_rows(
    config.fetch(:point_rows),
    start_time,
    opening_elapsed: config.fetch(:opening_elapsed),
    vbat_drop_per_second: config.fetch(:vbat_drop_per_second)
  )
  summary = metrics.summary(points, sensor_count: sensors.size)
  jump = flight_import.jumps.order(:id).first_or_initialize
  flight_import.jumps.where.not(id: jump.id).destroy_all if jump.persisted?
  jump.assign_attributes(
    {
      name: config.fetch(:name),
      location: config.fetch(:location),
      notes: config.fetch(:notes),
      exit_at: start_time,
      opening_at: start_time + config.fetch(:opening_elapsed),
      landing_at: start_time + config.fetch(:landing_elapsed)
    }.merge(summary)
  )
  jump.save!
  jump.track_points.delete_all
  jump.sensor_samples.delete_all

  now = Time.current
  TrackPoint.insert_all!(
    points.map do |point|
      point.slice(
        :recorded_at, :elapsed_seconds, :lat, :lon, :altitude_m, :vel_n_mps, :vel_e_mps, :vel_d_mps,
        :heading_deg, :horizontal_accuracy_m, :vertical_accuracy_m, :speed_accuracy_mps, :satellite_count,
        :gps_fix, :horizontal_speed_mps, :vertical_speed_mps, :glide_ratio, :distance_from_start_m
      ).merge(jump_id: jump.id, created_at: now, updated_at: now)
    end
  )

  SensorSample.insert_all!(
    sensors.map { |sample| sample.merge(jump_id: jump.id, created_at: now, updated_at: now) }
  )

  jump
end

if Rails.env.development? || ENV["LOAD_DEMO_DATA"].present?
  DEMO_FLIGHTS.each do |config|
    jump = seed_synthetic_flight(config)
    puts "Seeded #{jump.name}"
  end
end
