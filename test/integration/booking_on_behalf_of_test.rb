require "test_helper"

# A trip can be booked on behalf of a work or interest group, and is then charged
# at that group's rate. Only members of a group may charge it.
class BookingOnBehalfOfTest < ActionDispatch::IntegrationTest
  setup { BillingCategory.seed_defaults! }

  def member(name = "Anna", admin: false)
    User.create!(discourse_id: SecureRandom.random_number(1_000_000_000), name: name,
                 email: "#{SecureRandom.hex(4)}@example.com", user_type: "resident", admin: admin)
  end

  def car
    @car ||= begin
      rt = ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km", sort_order: 1)
      c = Resource.create!(name: "VW", port: "E-46", status: "active", resource_type: rt)
      c.resource_prices.create!(user_type: "resident", hour_rate: 10, day_rate: 0, km_rate: 2.5, min_charge: 0)
      c
    end
  end

  def garden
    @garden ||= BillingGroup.create!(name: "Garden", code: "GARDEN",
                                     billing_category: BillingCategory.find_by!(key: "ks_arbejdsgruppe"))
  end

  def sign_in(u) = get("/test/sign_in/#{u.id}")

  test "the dropdown offers only groups the person belongs to" do
    anna = member("Anna")
    BillingGroup.create!(name: "Workshop", billing_category: BillingCategory.find_by!(key: "ks_arbejdsgruppe"))
    garden.billing_group_memberships.create!(user: anna)
    sign_in(anna)

    get new_booking_path(resource_id: car.id, date: Date.current)

    assert_response :success
    assert_match "Garden", @response.body
    assert_no_match(/Workshop/, @response.body, "a group she is not in must not be offered")
  end

  test "a member can book on behalf of their group" do
    anna = member("Anna")
    garden.billing_group_memberships.create!(user: anna)

    booking = Booking.new(resource: car, user: anna, destination: "Town", billing_group: garden,
                          start_at: 2.hours.from_now, end_at: 4.hours.from_now, status: "active")
    assert booking.valid?, booking.errors.full_messages.to_sentence
    assert_equal "Garden", booking.billed_to
    assert_equal "ks_arbejdsgruppe", booking.effective_billing_category.key
  end

  test "a non-member cannot charge a group, even by a crafted request" do
    mikkel = member("Mikkel")
    booking = Booking.new(resource: car, user: mikkel, destination: "Town", billing_group: garden,
                          start_at: 2.hours.from_now, end_at: 4.hours.from_now, status: "active")

    assert_not booking.valid?
    assert booking.errors[:billing_group].any?
  end

  test "admins may charge any group, since they fix mistakes at month end" do
    boss = member("Admin", admin: true)
    booking = Booking.new(resource: car, user: boss, destination: "Town", billing_group: garden,
                          start_at: 2.hours.from_now, end_at: 4.hours.from_now, status: "active")
    assert booking.valid?, booking.errors.full_messages.to_sentence
  end

  test "booking personally falls back to the person's own category" do
    anna = member("Anna")
    anna.update!(billing_category: BillingCategory.find_by!(key: "hp"))

    booking = Booking.new(resource: car, user: anna, destination: "Town",
                          start_at: 2.hours.from_now, end_at: 4.hours.from_now, status: "active")
    assert booking.valid?
    assert_nil booking.billing_group
    assert_equal "hp", booking.effective_billing_category.key
    assert_equal "Anna", booking.billed_to
  end

  test "the group's rate wins over the driver's own rate" do
    anna = member("Anna")
    anna.update!(billing_category: BillingCategory.find_by!(key: "member")) # x1
    garden.billing_group_memberships.create!(user: anna)

    booking = Booking.new(resource: car, user: anna, billing_group: garden)
    # 100 km on behalf of Garden is the state rate, not Anna's normal rate.
    assert_equal 394.00, booking.effective_billing_category.charge_for(normal_amount: 250.00, km: 100).to_f
  end
end
