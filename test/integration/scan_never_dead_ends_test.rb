require "test_helper"

# The scan page must never tell somebody they have no booking when they do:
# a refused late return leaves the trip open and bills the extra time. These
# tests sweep the clock across and well beyond a reservation.
class ScanNeverDeadEndsTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  # 09:00–17:00 on a fixed day, so every offset below is easy to reason about.
  START = Time.zone.local(2026, 9, 15, 9, 0)
  FINISH = Time.zone.local(2026, 9, 15, 17, 0)

  teardown { travel_back }

  def user
    @user ||= User.create!(discourse_id: SecureRandom.random_number(1_000_000_000),
                           name: "Fører", email: "#{SecureRandom.hex(5)}@example.com",
                           user_type: "resident")
  end

  def car(rules: {})
    rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km",
                              sort_order: 1, booking_rules: rules)
    c = Resource.create!(name: "E-#{SecureRandom.hex(3)}", status: "active", resource_type: rt)
    c.create_resource_stat!(data: { "mileage" => 1000 })
    c
  end

  def booking_on(c, status: "active", **overrides)
    attrs = { resource: c, user: user, destination: "Town", start_at: START,
              end_at: FINISH, status: status }
    attrs.merge!(checked_in_at: START, start_mileage: 1000) if status == "awaiting_return"
    Booking.create!(**attrs.merge(overrides))
  end

  def dead_end?
    @response.body.include?(I18n.t("reservations.status.no_active"))
  end

  # Offsets relative to the booked window, in minutes, covering: long before,
  # just before, throughout, moments after, and a full two days late.
  OFFSETS_FROM_START = [-720, -240, -31, -30, -29, -4, -1, 0, 1, 60, 240].freeze
  OFFSETS_FROM_END   = [-1, 0, 1, 3, 10, 11, 60, 61, 180, 1440, 2880].freeze

  test "a trip that has not been ended is always shown, at every point on the clock" do
    %w[active awaiting_return].each do |status|
      [{}, { "checkout" => { "buffer_minutes" => 0 } },
           { "checkin"  => { "buffer_minutes" => 0 } },
           { "checkout" => { "buffer_minutes" => 0 }, "checkin" => { "buffer_minutes" => 0 } }].each do |rules|
        c = car(rules: rules)
        booking_on(c, status: status)

        offsets = OFFSETS_FROM_START.map { |m| START + m.minutes } +
                  OFFSETS_FROM_END.map   { |m| FINISH + m.minutes }

        offsets.each do |moment|
          travel_to(moment) do
            get vehicle_scan_path(c.qr_token)
            assert_response :success
            assert_not dead_end?,
                       "dead end at #{moment.strftime('%H:%M')} " \
                       "(status #{status}, rules #{rules.inspect})"
          end
        end
      end
    end
  end

  test "a late driver can still end the trip, however late they are" do
    [1, 3, 11, 61, 180, 1440, 2880, 10_080].each do |minutes_late|
      c = car
      booking_on(c, status: "awaiting_return")
      travel_to(FINISH + minutes_late.minutes) do
        get vehicle_scan_path(c.qr_token)
        assert_match I18n.t("reservations.completion.end_button"), @response.body,
                     "no way to end the trip #{minutes_late} minutes late"
      end
    end
  end

  test "a driver who is still out wins over someone arriving early for the next slot" do
    c = car
    still_out = booking_on(c, status: "awaiting_return")
    next_up   = booking_on(c, start_at: FINISH + 90.minutes, end_at: FINISH + 5.hours)

    # 20 minutes into the next driver's check-out buffer, with the first trip
    # still open: the unclosed trip is the one that needs dealing with.
    travel_to(FINISH + 70.minutes) do
      get vehicle_scan_path(c.qr_token)
      assert_match still_out.start_at.strftime("%H:%M"), @response.body
      assert_match I18n.t("reservations.completion.end_button"), @response.body
      assert_no_match(/#{Regexp.escape(next_up.start_at.strftime("%a %-d %b, %H:%M"))}/, @response.body)
    end
  end

  test "an idle car with nothing booked still says so" do
    c = car
    travel_to(START) do
      get vehicle_scan_path(c.qr_token)
      assert dead_end?, "an idle vehicle should still report that it is free"
    end
  end

  test "a cancelled booking does not resurrect as an active reservation" do
    c = car
    booking_on(c, status: "cancelled")
    travel_to(START + 60.minutes) do
      get vehicle_scan_path(c.qr_token)
      assert dead_end?
    end
  end

  test "a returned booking is not re-offered for ending" do
    c = car
    booking_on(c, status: "returned", completed_at: FINISH, end_mileage: 1100)
    travel_to(FINISH + 3.hours) do
      get vehicle_scan_path(c.qr_token)
      assert dead_end?, "a finished trip must not come back as still out"
    end
  end
end
