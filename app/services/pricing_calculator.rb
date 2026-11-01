# Single source of truth for what a reservation costs.
#
# Given a booking (and, for distance-billed resources, the start/ending odometer
# readings), it produces a cost breakdown. The four entry points that complete a
# reservation all price through here so the charge can't drift between them.
#
# Charge model:
#   total = time_cost + km_cost + toll_cost + accessory_cost
#
#   time_cost      parent resource's time price (0 for `free` resource types)
#   km_cost        odometer delta × km_rate   (only `per_day_and_km` resources)
#   toll_cost      Toll booking_accessories: unit price × quantity
#   accessory_cost non-toll accessory shadow-bookings, priced on their own resource
#
# Accessories are separate shadow-bookings but are billed here, at the parent's
# completion, and never on their own.
class PricingCalculator
  Breakdown = Data.define(:time_cost, :km_cost, :toll_cost, :accessory_cost) do
    def total
      time_cost + km_cost + toll_cost + accessory_cost
    end
  end

  # start_odometer / ending_reading are only consulted for per_day_and_km resources.
  def initialize(booking, start_odometer: nil, ending_reading: nil)
    @booking        = booking
    @resource       = booking.resource
    @user_type      = booking.user.user_type
    @start_odometer = start_odometer
    @ending_reading = ending_reading
  end

  def breakdown
    b = Breakdown.new(
      time_cost:      time_cost,
      km_cost:        km_cost,
      toll_cost:      toll_cost,
      accessory_cost: accessory_cost
    )
    car? ? apply_car_minimum(b) : b
  end

  private

  def billing_type
    @resource.resource_type.billing_type
  end

  def car?
    billing_type == "per_day_and_km"
  end

  # Floor a car's driving cost (time + km together) at the site-wide car minimum —
  # the lower home minimum for home cars. Below it, the reservation is rounded up
  # to the minimum; at or above, the actual cost stands. The top-up is folded into
  # time_cost so the breakdown still sums to the total. Tolls and accessories sit
  # on top and are not part of the minimum.
  def apply_car_minimum(b)
    minimum = SiteSetting.instance.minimum_for(@resource)
    driving = b.time_cost + b.km_cost
    return b if driving >= minimum

    b.with(time_cost: b.time_cost + (minimum - driving))
  end

  def price
    @price ||= @resource.price_for(@user_type)
  end

  # Prorated for early returns via Booking#billed_hours (reads completed_at).
  def hours
    @booking.billed_hours
  end

  # Time price of the parent resource. `free` resource types cost nothing for time.
  # Cars skip the per-price min_charge here — their minimum is applied to time + km
  # combined in apply_car_minimum.
  def time_cost
    return 0 if billing_type == "free"
    return 0 unless price

    price.calculate_time_cost(hours, apply_min: !car?)
  end

  # Distance charge — only meaningful for per_day_and_km resources, and only once
  # we know both the start reading and the ending reading.
  def km_cost
    return 0 unless billing_type == "per_day_and_km"
    return 0 unless price && @ending_reading && @start_odometer

    km = @ending_reading - @start_odometer
    return 0 if km <= 0

    km * price.km_rate
  end

  # One-time tolls attached to this booking (bridge crossings etc.). They only exist
  # on the parent booking, so they must be billed here. Priced at the toll resource's
  # hour_rate (used as a flat unit price) × quantity.
  def toll_cost
    toll_accessories.sum do |ba|
      unit = ba.accessory.price_for(@user_type)&.hour_rate || 0
      unit * ba.quantity
    end
  end

  # Non-toll accessories (child seats, racks, …). Each is a shadow-booking on its own
  # resource for the same window; priced on that resource's own time rate.
  def accessory_cost
    @booking.accessory_bookings
            .where(status: %w[active awaiting_return])
            .includes(resource: [:resource_type, :resource_prices])
            .sum do |shadow|
      acc_price = shadow.resource.price_for(@user_type)
      acc_price ? acc_price.calculate_time_cost(hours) : 0
    end
  end

  def toll_accessories
    @booking.booking_accessories
            .includes(accessory: :resource_type)
            .select { |ba| ba.accessory.resource_type&.name == "Toll" }
  end
end
