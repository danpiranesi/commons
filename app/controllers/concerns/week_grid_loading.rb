# Shared week-grid data loading for the calendar dashboard and the public wall
# schedule, so the two can't drift on which bookings are shown (e.g. including
# `returned` for the faded early-return marker). `_week_grid` needs exactly four
# ivars; this builds the booking query both feed it.
module WeekGridLoading
  extend ActiveSupport::Concern

  def week_days(week_start)
    (week_start..(week_start + 6.days)).to_a
  end

  # { resource_id => [bookings] } for the given resources within the week window.
  # `returned` is included so an early return leaves a faded marker rather than
  # vanishing; the freed remainder is still bookable (overlap checks ignore it).
  def bookings_by_resource_for(resources, week_start, week_end)
    Booking
      .where(resource_id: resources.select(:id))
      .where(status: %w[active awaiting_return returned])
      .where("start_at < ? AND end_at > ?", week_end.end_of_day, week_start.beginning_of_day)
      .includes(:user, :billing_group, parent_booking: :resource)
      .group_by(&:resource_id)
  end
end
