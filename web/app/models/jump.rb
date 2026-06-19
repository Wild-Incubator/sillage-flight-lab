class Jump < ApplicationRecord
  VIDEO_PROCESSING_STATUSES = %w[empty processing ready failed].freeze
  VIDEO_UPLOAD_EXTENSIONS = %w[.avi .m4v .mkv .mov .mp4 .webm].freeze

  belongs_to :flight_import
  has_many :track_points, dependent: :delete_all
  has_many :sensor_samples, dependent: :delete_all
  has_one_attached :video_upload
  has_one_attached :video

  validates :name, presence: true
  validates :video_processing_status, inclusion: { in: VIDEO_PROCESSING_STATUSES }
  validates :video_exit_offset_seconds, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :video_duration_seconds, numericality: { greater_than: 0 }, allow_nil: true
  validate :video_upload_must_be_video

  scope :recent, -> { order(started_at: :desc, created_at: :desc) }

  def bounds
    [ exit_at || started_at, opening_at, landing_at || ended_at ].compact
  end

  def display_started_at
    started_at || flight_import.log_started_at || created_at
  end

  def height_m
    return nil unless min_altitude_m && max_altitude_m

    max_altitude_m - min_altitude_m
  end

  def video_ready?
    video_processing_status == "ready" && video.attached?
  end

  def video_processing?
    video_processing_status == "processing"
  end

  def video_failed?
    video_processing_status == "failed"
  end

  private

  def video_upload_must_be_video
    return unless video_upload.attached?
    return if video_upload.blob.content_type&.start_with?("video/")
    return if VIDEO_UPLOAD_EXTENSIONS.include?(video_upload.blob.filename.extension_with_delimiter.downcase)

    errors.add(:video_upload, :invalid)
  end
end
