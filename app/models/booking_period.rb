class BookingPeriod < ApplicationRecord
  STATUSES = %w[draft scheduled open closed].freeze

  has_many :bookings, dependent: :restrict_with_error

  validates :name, presence: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validate :end_date_after_start_date

  scope :open, -> { where(status: "open") }

  def open?
    status == "open"
  end

  def covers?(date)
    (start_date..end_date).cover?(date)
  end

  private

  def end_date_after_start_date
    return unless start_date && end_date
    errors.add(:end_date, "must be after start date") if end_date <= start_date
  end
end
