# App-wide settings, edited by admins. Single-row (singleton) table: use
# SiteSetting.instance everywhere rather than querying directly.
#
#   SiteSetting.instance.homepage_header   # => the banner text for the current locale
class SiteSetting < ApplicationRecord
  # Starting destination list, used until an admin edits it on the settings page
  # (Indstillinger → Destinationer). Stored as an ordered array so group order is
  # preserved.
  #
  # A few common places plus rough distances, so a driver going somewhere not on
  # the list can still say how far the car is going. Free text covers the rest;
  # a long list is slower on a phone than typing.
  DEFAULT_DESTINATIONS = [
    { "group" => "Nærområdet",
      "cities" => ["Indkøb", "Togstation", "Lægen"] },
    { "group" => "Længere væk",
      "cities" => ["Hospital", "Lufthavn"] },
    { "group" => "Omtrentlig afstand",
      "cities" => ["Under 25 km", "25–50 km", "50–100 km", "100–200 km", "Over 200 km"] }
  ].freeze

  # The one and only row, created on first access.
  def self.instance
    first || create!
  end

  # Ordered [{ "group" =>, "cities" => [...] }] — admin-edited or the default.
  def destination_list
    list = destinations.presence
    list.is_a?(Array) ? list : DEFAULT_DESTINATIONS
  end

  # The minimum a given car reservation costs (time + km combined). Home cars use
  # the lower home minimum. Callers should only ask this for cars.
  def minimum_for(resource)
    resource&.home_car? ? home_car_minimum_price : car_minimum_price
  end

  # Longest a home car may be booked in one go, or nil when unlimited (0).
  def home_car_max_hours_limit
    home_car_max_hours.to_i.positive? ? home_car_max_hours.to_i : nil
  end

  # The last date a member may book, or nil when booking ahead is unlimited
  # (horizon set to 0).
  def booking_horizon_date
    booking_horizon_days.positive? ? Date.current + booking_horizon_days : nil
  end

  # Whether the given date is within the booking horizon (always true when
  # unlimited).
  def within_booking_horizon?(date)
    horizon = booking_horizon_date
    horizon.nil? || date <= horizon
  end

  # Whether a member may book on `date`: not in the past, and within the rolling
  # horizon (today .. today + booking_horizon_days). Admins bypass both limits.
  def bookable_date?(date, admin: false)
    return true if admin
    return false if date < Date.current

    within_booking_horizon?(date)
  end

  # Banner text for the current locale, falling back to the other locale so a
  # single-language entry still shows for everyone.
  def homepage_header
    locale_text(I18n.locale).presence ||
      homepage_header_da.presence ||
      homepage_header_en.presence
  end

  private

  def locale_text(locale)
    case locale.to_s
    when "en" then homepage_header_en
    else homepage_header_da
    end
  end
end
