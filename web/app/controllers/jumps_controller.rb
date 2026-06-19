class JumpsController < ApplicationController
  before_action :set_jump, only: [ :show, :update, :destroy ]

  def index
    @jumps = Jump.recent.includes(:flight_import)
  end

  def show
    @track_points = sampled_track_points(limit: 2_000)
    @sensor_samples = sampled_sensor_samples(limit_per_type: 1_200)
    @sensor_counts = @jump.sensor_samples.group(:sensor_type).count
    @ground_altitude_m = @jump.min_altitude_m || @track_points.filter_map(&:altitude_m).min
    @visualization_points = @track_points.map { |point| serialize_point(point) }
    @visualization_sensors = @sensor_samples.map { |sample| serialize_sensor_sample(sample) }
    @cesium_ion_token = cesium_ion_token
    @bounds = {
      exit: elapsed_for(@jump.exit_at),
      opening: elapsed_for(@jump.opening_at),
      landing: elapsed_for(@jump.landing_at)
    }.compact
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
    {
      type: sample.sensor_type,
      t: sample.elapsed_seconds&.round(3),
      readings: sample.readings || {}
    }
  end

  def height_from_ground(altitude)
    return nil unless altitude && @ground_altitude_m

    [ altitude.to_f - @ground_altitude_m.to_f, 0.0 ].max
  end

  def elapsed_for(timestamp)
    return nil unless timestamp && @jump.started_at

    (timestamp - @jump.started_at).round(3)
  end
end
