class ResourcePrice < ApplicationRecord
  belongs_to :resource

  validates :user_type, presence: true, inclusion: { in: User::USER_TYPES }
  validates :user_type, uniqueness: { scope: :resource_id }
  validates :hour_rate, :day_rate, :km_rate, :min_charge, numericality: { greater_than_or_equal_to: 0 }

  # Time price for a duration. `apply_min` floors the result at this price's
  # min_charge — the default, and how bikes/accessories work. Cars pass
  # apply_min: false because their minimum is the site-wide car minimum applied to
  # time + km combined (see PricingCalculator), not this per-price floor.
  def calculate_time_cost(hours, apply_min: true)
    return 0 if hours <= 0

    if hour_rate > 0
      # Hourly pricing with optional day cap
      if day_rate > 0 && day_cap_hours > 0
        full_days = (hours / 24).floor
        remaining_hours = hours - (full_days * 24)

        day_cost = full_days * day_rate
        remaining_cost = remaining_hours * hour_rate
        remaining_cost = [remaining_cost, day_rate].min if remaining_hours >= day_cap_hours

        total = day_cost + remaining_cost
      else
        total = hours * hour_rate
      end
    elsif day_rate > 0
      # Day-rate only — use day_cap_hours as the day boundary if set, else 24h
      hours_per_day = (day_cap_hours > 0 ? day_cap_hours : 24).to_f
      days = (hours / hours_per_day).ceil
      days = 1 if days == 0
      total = days * day_rate
    else
      return 0
    end

    apply_min ? [total, min_charge].max : total
  end
end
