module UsageHelper
  # Totals for one month's worth of the current member's own bookings. Trips
  # made on behalf of a group are the group's and are left out by the caller.
  def month_total(bookings)
    {
      cost:  bookings.sum { |b| b.total_amount || 0 },
      km:    bookings.sum { |b| b.km_driven || 0 },
      hours: bookings.sum(&:billed_hours),
      count: bookings.size
    }
  end
end
