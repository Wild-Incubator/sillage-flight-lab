class FlightImport < ApplicationRecord
  STATUSES = %w[pending processing imported failed].freeze

  has_many :jumps, dependent: :destroy
  has_many_attached :source_files

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  def imported?
    status == "imported"
  end

  def failed?
    status == "failed"
  end
end
