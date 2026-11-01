module BookingsHelper
  # The resource as the booking pages title it (the admin-designed card title).
  def booking_resource_title(resource)
    ResourceCardTemplate.new(resource).title.presence || resource.name
  end

  def booking_status_variant(booking)
    case booking.status
    when "active" then :success
    when "cancelled" then :danger
    when "awaiting_return" then :warning
    else :default
    end
  end

  # The minimum a car reservation will be floored to (time + km combined), for the
  # estimate. Reflects the category multiplier — a double-rate person's floor is
  # 2× — and is nil for non-cars and for state-rate trips, which bill purely on km
  # with no minimum. Shared by the live price preview and the booking detail view.
  def car_minimum_for(resource, category)
    return nil unless resource&.car?
    return nil if category&.per_km?
    base = SiteSetting.instance.minimum_for(resource)
    category&.multiplier? ? (base * category.rate_value) : base
  end
end
