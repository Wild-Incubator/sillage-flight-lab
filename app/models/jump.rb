class Jump < ApplicationRecord
  belongs_to :flight_import
  has_many :track_points, dependent: :delete_all
  has_many :sensor_samples, dependent: :delete_all

  validates :name, presence: true

  scope :recent, -> { order(started_at: :desc, created_at: :desc) }

  def bounds
    [ exit_at || started_at, opening_at, landing_at || ended_at ].compact
  end

  def display_started_at
    started_at || flight_import.log_started_at || created_at
  end
end
