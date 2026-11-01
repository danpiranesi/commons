class CalendarController < ApplicationController
  include WeekGridLoading

  def show
    @date = params[:date] ? Date.parse(params[:date]) : Date.current
    @week_start = @date.beginning_of_week(:monday)
    @week_end = @week_start + 6.days
    @days = (@week_start..@week_end).to_a

    # Mobile only: "book" (the booking wizard, default) or the weekly calendar.
    @mobile_view = params[:view] == "week" ? "week" : "book"
    @mobile_view_param = (@mobile_view == "week" ? "week" : nil)

    @resource_type_id = params[:resource_type_id]
    @resource_types = ResourceType.ordered
    # Rolling horizon: today is always bookable, and the mobile picker runs up to
    # the horizon (nil = unlimited).
    @booking_horizon_end = SiteSetting.instance.booking_horizon_date

    hidden_type_ids = @resource_types.select { |rt| rt.name == "Toll" }.map(&:id)
    resources_scope = Resource.where(status: %w[active unavailable]).where.not(resource_type_id: hidden_type_ids).includes(:resource_type, :resource_prices)
    if params[:filter] == "other"
      other_type_ids = @resource_types.reject { |rt| rt.name.in?(%w[Car Bicycle Toll]) }.map(&:id)
      resources_scope = resources_scope.where(resource_type_id: other_type_ids)
    elsif @resource_type_id.present?
      resources_scope = resources_scope.where(resource_type_id: @resource_type_id)
    end
    # regular_user is preloaded because every empty grid cell asks whether the car
    # is still held for its fast bruger.
    @resources = resources_scope.joins(:resource_type).includes(:regular_user)
                                .order("resource_types.sort_order, resources.name")

    @bookings = Booking.where(resource_id: @resources.select(:id))
      .where(status: %w[active awaiting_return])
      .where("start_at < ? AND end_at > ?", @week_end.end_of_day, @week_start.beginning_of_day)
      .includes(:user, :billing_group, parent_booking: :resource)
      .index_by { |b| [b.resource_id, b.start_at.to_date] }

    @bookings_by_resource = bookings_by_resource_for(@resources, @week_start, @week_end)

    load_active_booking_panel
    load_upcoming_bookings
  end

  private

  # The current user's future reservations (not yet started, not the one already
  # shown in the active panel) — rendered as small editable cards above the grid.
  def load_upcoming_bookings
    scope = current_user.bookings
      .where(status: %w[active awaiting_return], parent_booking_id: nil)
      .where("start_at > ?", Time.current)
      .includes(resource: :resource_type)
      .order(:start_at)
    scope = scope.where.not(id: @active_booking.id) if @active_booking
    @upcoming_bookings = scope
  end

  # The pinned "active booking" panel: the current user's own reservation whose
  # window is open right now (top-level only, never an accessory shadow), plus the
  # next reservation on that resource if it starts within 30 min of this one
  # ending, for the close-transfer call feature.
  def load_active_booking_panel
    # Everything of theirs that has started (or is about to) and is still open.
    # No lower bound on end_at: a trip that ran past its return time and was never
    # closed must stay on the panel, because that panel is where the driver ends
    # it. Each booking's own buffers are then applied via actionable_at?.
    open_bookings = current_user.bookings
      .where(status: %w[active awaiting_return], parent_booking_id: nil, completed_at: nil)
      .where("start_at <= ?", Time.current + 180.minutes)
      .includes(resource: :resource_type).order(:start_at).to_a

    # A trip whose window is open right now wins; otherwise show the most recent
    # unclosed one, so a forgotten return is the thing staring back at them.
    @active_booking = open_bookings.find { |b| b.window_open_at? } ||
                      open_bookings.select(&:actionable_at?).max_by(&:end_at)
    return unless @active_booking

    @next_booking = @active_booking.resource.bookings
      .where(status: %w[active awaiting_return], parent_booking_id: nil)
      .where.not(id: @active_booking.id)
      .where("start_at >= ? AND start_at <= ?", @active_booking.end_at, @active_booking.end_at + 30.minutes)
      .includes(:user).order(:start_at).first
  end
end
