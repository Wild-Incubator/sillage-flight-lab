class JumpsController < ApplicationController
  before_action :set_jump, only: [ :show, :update, :destroy ]

  def index
    @query = params[:q].to_s.strip
    @jumps = Jump.recent.includes(:flight_import)
    return if @query.blank?

    pattern = "%#{Jump.sanitize_sql_like(@query)}%"
    @jumps = @jumps.where("jumps.name LIKE :pattern OR jumps.location LIKE :pattern", pattern:)
  end

  def show
    @track_points = sampled_track_points(limit: 2_000)
    @sensor_samples = sampled_sensor_samples(limit_per_type: 1_200)
    @sensor_counts = @jump.sensor_samples.group(:sensor_type).count
    @ground_altitude_m = @jump.min_altitude_m || @track_points.filter_map(&:altitude_m).min
    @flight_analysis = Jumps::FlightAnalysis.new(
      track_points: @track_points,
      sensor_samples: @sensor_samples,
      origin_time: @jump.started_at
    ).call
    @analysis = analysis_payload(@flight_analysis)
    @replay_elapsed_range = replay_elapsed_range(@flight_analysis)
    @visualization_points = @track_points.select { |point| in_replay_window?(point.elapsed_seconds) }.map { |point| serialize_point(point) }
    @visualization_sensors = @sensor_samples.select { |sample| in_replay_window?(sensor_elapsed_seconds(sample)) }.map { |sample| serialize_sensor_sample(sample) }
    @cesium_ion_token = cesium_ion_token
    @bounds = bounds_payload(@flight_analysis.bounds)
  end

  def update
    attributes = jump_params
    video_upload = attributes.delete(:video_upload)

    if video_upload.present? && !video_upload?(video_upload)
      redirect_to @jump, alert: t(".video_invalid")
      return
    end

    if @jump.update(attributes)
      enqueue_video_processing(video_upload) if video_upload.present?
      redirect_to @jump, notice: t(".success")
    else
      redirect_to @jump, alert: @jump.errors.full_messages.to_sentence
    end
  end

  def destroy
    @jump.destroy!
    redirect_to jumps_path, notice: t(".success")
  end

  private

  def set_jump
    @jump = Jump.find(params[:id])
  end

  def cesium_ion_token
    ENV["CESIUM_ION_TOKEN"].presence ||
      Rails.application.credentials.dig(:cesium, :ion_token).presence
  end

  def jump_params
    params.require(:jump).permit(
      :name,
      :location,
      :notes,
      :exit_at,
      :opening_at,
      :landing_at,
      :video_upload,
      :video_exit_offset_seconds
    )
  end

  def video_upload?(upload)
    upload.content_type&.start_with?("video/") ||
      Jump::VIDEO_UPLOAD_EXTENSIONS.include?(File.extname(upload.original_filename.to_s).downcase)
  end

  def enqueue_video_processing(video_upload)
    @jump.video_upload.purge_later if @jump.video_upload.attached?
    @jump.video.purge_later if @jump.video.attached?
    @jump.video_upload.attach(video_upload)
    @jump.update!(
      video_processing_status: "processing",
      video_processing_error: nil,
      video_exit_offset_seconds: nil,
      video_duration_seconds: nil
    )
    JumpVideoProcessingJob.perform_later(@jump)
  end

  def downsample(records, limit:)
    return records if records.size <= limit

    step = (records.size.to_f / limit).ceil
    records.each_with_index.filter_map { |record, index| record if (index % step).zero? }
  end

  def sampled_track_points(limit:)
    scope = @jump.track_points.ordered
    count = scope.count
    return scope.to_a if count <= limit

    step = (count.to_f / limit).ceil
    TrackPoint.find_by_sql([ <<~SQL.squish, @jump.id, step ])
      SELECT *
      FROM (
        SELECT track_points.*, ROW_NUMBER() OVER (ORDER BY elapsed_seconds, recorded_at) AS row_index
        FROM track_points
        WHERE jump_id = ?
      )
      WHERE ((row_index - 1) % ?) = 0
      ORDER BY elapsed_seconds, recorded_at
    SQL
  end

  def sampled_sensor_samples(limit_per_type:)
    @jump.sensor_samples.distinct.pluck(:sensor_type).flat_map do |sensor_type|
      scope = @jump.sensor_samples.where(sensor_type: sensor_type).ordered
      count = scope.count
      next scope.to_a if count <= limit_per_type

      step = (count.to_f / limit_per_type).ceil
      SensorSample.find_by_sql([ <<~SQL.squish, @jump.id, sensor_type, step ])
        SELECT *
        FROM (
          SELECT sensor_samples.*, ROW_NUMBER() OVER (ORDER BY elapsed_seconds, recorded_at) AS row_index
          FROM sensor_samples
          WHERE jump_id = ? AND sensor_type = ?
        )
        WHERE ((row_index - 1) % ?) = 0
        ORDER BY elapsed_seconds, recorded_at
      SQL
    end
  end

  def serialize_point(point)
    {
      t: point.elapsed_seconds&.round(3),
      lat: point.lat,
      lon: point.lon,
      alt: point.altitude_m,
      height: height_from_ground(point.altitude_m),
      hspeed: point.horizontal_speed_mps,
      vspeed: point.vertical_speed_mps,
      glide: point.glide_ratio,
      distance: point.distance_from_start_m
    }
  end

  def serialize_sensor_sample(sample)
    readings = sample.readings || {}
    readings = readings.merge("pressure_altitude_m" => pressure_altitude(readings["pressure"])) if sample.sensor_type == "BARO" && readings["pressure_altitude_m"].blank?

    {
      type: sample.sensor_type,
      t: sensor_elapsed_seconds(sample)&.round(3),
      readings: readings
    }
  end

  def height_from_ground(altitude)
    return nil unless altitude && @ground_altitude_m

    [ altitude.to_f - @ground_altitude_m.to_f, 0.0 ].max
  end

  def sensor_elapsed_seconds(sample)
    return sample.recorded_at - @jump.started_at if sample.recorded_at && @jump.started_at

    sample.elapsed_seconds
  end

  def pressure_altitude(pressure)
    return nil if pressure.blank?

    pressure = pressure.to_f
    44_330.0 * (1.0 - (pressure / 101_325.0)**0.190294957)
  end

  def analysis_payload(analysis)
    analysis.to_h.except(:bounds).merge(
      timeline_start: analysis.timeline_start&.round(3),
      timeline_end: analysis.timeline_end&.round(3),
      replay_start: analysis.replay_start&.round(3),
      replay_end: analysis.replay_end&.round(3),
      altitude_min: analysis.altitude_min&.round(3),
      altitude_max: analysis.altitude_max&.round(3)
    )
  end

  def replay_elapsed_range(analysis)
    analysis.replay_start..analysis.replay_end
  end

  def in_replay_window?(elapsed_seconds)
    return true unless @replay_elapsed_range
    return false unless elapsed_seconds

    @replay_elapsed_range.cover?(elapsed_seconds.to_f)
  end

  def bounds_payload(bounds)
    {
      exit: elapsed_for(bounds[:exit_at]),
      opening: elapsed_for(bounds[:opening_at]),
      landing: elapsed_for(bounds[:landing_at])
    }.compact
  end

  def elapsed_for(timestamp)
    return nil unless timestamp && @jump.started_at

    (timestamp - @jump.started_at).round(3)
  end
end
