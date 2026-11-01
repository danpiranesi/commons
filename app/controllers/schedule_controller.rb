# Public weekly schedule for the wall-mounted display on-site. No login
# to *read* it; tapping an open slot to book routes through the normal booking
# flow, which bounces to login and returns to the slot (return-to in
# ApplicationController#authenticate_user!). Cars only, current week.
class ScheduleController < ApplicationController
  include WeekGridLoading

  skip_before_action :authenticate_user!, only: :show
  layout "minimal"

  def show
    @week_start = Date.current.beginning_of_week(:monday)
    @week_end   = @week_start + 6.days
    @days       = week_days(@week_start)

    @resources = Resource
      .where(status: %w[active unavailable])
      .joins(:resource_type)
      .where(resource_types: { name: "Car" })
      .includes(:resource_type, :resource_prices, :regular_user)
      .order("resources.name")

    @bookings_by_resource = bookings_by_resource_for(@resources, @week_start, @week_end)
  end
end
