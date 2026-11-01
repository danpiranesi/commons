module CalendarHelper
  def day_names
    %w[Mon Tue Wed Thu Fri Sat Sun]
  end

  def bookings_for(resource, day, bookings_by_resource)
    (bookings_by_resource[resource.id] || []).select { |b|
      b.start_at.to_date <= day && booking_display_end(b).to_date >= day
    }.sort_by(&:start_at)
  end

  # Where a booking visually ends on the grid. A returned booking only occupies
  # the slot up to when it was actually returned (so the freed remainder shows as
  # open); everything else uses its booked end time.
  def booking_display_end(booking)
    if booking.status == "returned" && booking.completed_at
      booking.completed_at
    else
      booking.end_at
    end
  end

  def booking_spans_day?(booking, day)
    booking.start_at.to_date <= day && b_end_date(booking) >= day
  end

  def booking_starts_on?(booking, day)
    booking.start_at.to_date == day
  end

  def booking_ends_on?(booking, day)
    b_end_date(booking) == day
  end

  def booking_cell_classes(booking, day, week_start)
    starts = booking.start_at.to_date
    ends = b_end_date(booking)

    # Determine if this is the visual start of the span (either actual start or beginning of week)
    visual_start = [starts, week_start].max == day

    classes = []
    classes << "rounded-l-md" if visual_start
    classes << "rounded-r-md" if ends == day || day == week_start + 6.days
    classes.join(" ")
  end

  def format_time_range(booking)
    if booking.start_at.to_date == booking.end_at.to_date
      "#{booking.start_at.strftime('%H:%M')}–#{booking.end_at.strftime('%H:%M')}"
    else
      "#{booking.start_at.strftime('%-d %b %H:%M')} – #{booking.end_at.strftime('%-d %b %H:%M')}"
    end
  end

  def week_label(week_start)
    if week_start.month == (week_start + 6.days).month
      "#{week_start.strftime('%-d')}–#{(week_start + 6.days).strftime('%-d %B %Y')}"
    else
      "#{week_start.strftime('%-d %b')} – #{(week_start + 6.days).strftime('%-d %b %Y')}"
    end
  end

  def today?(day)
    day == Date.current
  end

  def past?(day)
    day < Date.current
  end

  # Whether a day can still be booked given the site's booking horizon. Admins are
  # never limited; the horizon is a member-facing rule.
  def bookable_day?(day)
    return true if admin?
    SiteSetting.instance.within_booking_horizon?(day)
  end

  # The fast bruger this car is still held for on `day`, or nil when anyone may
  # book it. Drives the "reserved for X" cell so a held slot never looks free.
  def held_by_name(resource, day)
    return nil unless resource.regular_user_id
    return nil unless resource.held_for?(day.beginning_of_day, day.end_of_day, current_user)
    resource.regular_driver_name
  end

  private

  def b_end_date(booking)
    # If end_at is midnight, the booking visually ends the day before
    if booking.end_at == booking.end_at.midnight
      booking.end_at.to_date - 1.day
    else
      booking.end_at.to_date
    end
  end
end
