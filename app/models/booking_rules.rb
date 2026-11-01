# Per-resource-type rules for the reservation lifecycle, authored on the admin
# Rules page (Booking → Check-out → During → Check-in). Stored as jsonb on
# ResourceType; absent values fall back to DEFAULTS.
#
#   rules = BookingRules.for(resource.resource_type)
#   rules.checkout_buffer_minutes   # => 30
#   rules.require_odometer?          # => true
class BookingRules
  # Lifecycle stages, in order — these are the flowchart nodes.
  STAGES = %w[booking checkout during checkin].freeze

  # The buffers are deliberately generous: a driver a few minutes early or late
  # must still find their booking, or the trip is never closed.
  DEFAULTS = {
    "booking"  => {},
    "checkout" => { "buffer_minutes" => 30, "require_odometer" => true },
    "during"   => { "allow_extension" => true, "edit_shorten_penalty_hours" => 2 },
    "checkin"  => { "buffer_minutes" => 60, "require_confirmation" => true, "max_km_per_trip" => 2000, "overdue_after_minutes" => 10, "grace_minutes" => 10 }
  }.freeze

  def self.for(resource_type)
    # Trailers, rocket boxes and tolls defer to the car's rules rather than their
    # own — they're attached to a car, not booked on their own terms.
    if resource_type&.inherit_rules_from_car? && (car = ResourceType.car) && car.id != resource_type.id
      resource_type = car
    end
    new(resource_type&.booking_rules)
  end

  def initialize(stored)
    @stored = stored.presence || {}
  end

  # Merged (defaults + stored) settings for one stage.
  def stage(name)
    DEFAULTS.fetch(name.to_s, {}).merge(@stored[name.to_s] || {})
  end

  # ── Check-out (start of trip) ─────────────────────────────
  # How many minutes before start_at a driver may check the car out (if it's free).
  def checkout_buffer_minutes = stage("checkout")["buffer_minutes"].to_i
  # Whether a starting odometer must be recorded before the car can be ended.
  def require_odometer? = truthy?(stage("checkout")["require_odometer"])

  # ── During ────────────────────────────────────────────────
  def allow_extension? = truthy?(stage("during")["allow_extension"])
  # Hours a driver stays billed for beyond a shortened end time, as a disincentive
  # against releasing a slot last-minute. 0 disables the penalty for this type.
  def edit_shorten_penalty_hours = stage("during")["edit_shorten_penalty_hours"].to_i

  # ── Check-in (return) ─────────────────────────────────────
  # How many minutes past end_at a driver may still return the car.
  def return_buffer_minutes = stage("checkin")["buffer_minutes"].to_i
  # Whether the "you drove X km — confirm?" screen is shown before finalising.
  def require_confirmation? = truthy?(stage("checkin")["require_confirmation"])
  # Sanity cap on a single trip's km before it's flagged as implausible.
  def max_km_per_trip = stage("checkin")["max_km_per_trip"].to_i
  # Minutes past end_at before a still-out booking is flagged overdue.
  def overdue_after_minutes = stage("checkin")["overdue_after_minutes"].to_i
  # Billing grace, in minutes. Time is billed in half-hour blocks; this much of a
  # started block is forgiven (rounds down), anything past it rounds up. The same
  # grace keeps a slightly late return billed at the booked end.
  def grace_minutes = stage("checkin")["grace_minutes"].to_i

  private

  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end
end
