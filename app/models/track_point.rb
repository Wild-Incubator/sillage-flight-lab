class TrackPoint < ApplicationRecord
  belongs_to :jump

  scope :ordered, -> { order(:elapsed_seconds, :recorded_at) }
end
