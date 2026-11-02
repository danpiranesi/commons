# Sample data for a fresh development database. Safe to re-run: everything is
# looked up before it is created, and the example bookings are only added when
# there are none yet.

car_type = ResourceType.find_or_create_by!(name: "Car") do |rt|
  rt.billing_type = "per_day_and_km"
  rt.icon = "car"
  rt.color = "#7A8C6E"
  rt.sort_order = 1
  rt.stats_schema = { "mileage" => "integer" }
end

bicycle_type = ResourceType.find_or_create_by!(name: "Bicycle") do |rt|
  rt.billing_type = "per_day"
  rt.icon = "bicycle"
  rt.color = "#5C7A4E"
  rt.sort_order = 2
end

trailer_type = ResourceType.find_or_create_by!(name: "Trailer") do |rt|
  rt.billing_type = "per_day"
  rt.icon = "trailer"
  rt.color = "#6B7C60"
  rt.sort_order = 3
end

# Prices are per user type. Residents pay the lower rate; employees the higher.
def seed_resource(type, name:, description:, rates:, mileage: nil)
  resource = Resource.find_or_create_by!(name: name) do |r|
    r.resource_type = type
    r.description = description
    r.status = "active"
  end

  rates.each do |user_type, price|
    ResourcePrice.find_or_create_by!(resource: resource, user_type: user_type.to_s) do |rp|
      rp.hour_rate  = price[:hour]
      rp.day_rate   = price[:day]
      rp.km_rate    = price.fetch(:km, 0)
      rp.min_charge = price.fetch(:min, 0)
    end
  end

  if mileage
    ResourceStat.find_or_create_by!(resource: resource) do |rs|
      rs.data = { "mileage" => mileage }
    end
  end

  resource
end

car_rates = {
  resident: { hour: 15, day: 150, km: 0.50, min: 25 },
  employee: { hour: 20, day: 200, km: 0.75, min: 25 }
}

[
  [ "VW Transporter (AB 12 345)", "White 9-seater van", 84_000 ],
  [ "Peugeot 308 (CD 67 890)", "Blue station wagon", 121_500 ],
  [ "Toyota Yaris (EF 11 222)", "Red compact", 42_300 ],
  [ "Skoda Octavia (GH 33 444)", "Silver estate", 97_800 ],
  [ "Fiat Ducato (IJ 55 666)", "Large delivery van", 63_100 ]
].each do |name, description, mileage|
  seed_resource(car_type, name: name, description: description, rates: car_rates, mileage: mileage)
end

bicycle_rates = {
  resident: { hour: 5, day: 50 },
  employee: { hour: 8, day: 75 }
}

[
  [ "E-bike 1", "Electric cargo bike" ],
  [ "E-bike 2", "Electric city bike" ],
  [ "Cargo bike", "Manual cargo bike" ]
].each do |name, description|
  seed_resource(bicycle_type, name: name, description: description, rates: bicycle_rates)
end

trailer_rates = {
  resident: { hour: 10, day: 100 },
  employee: { hour: 15, day: 150 }
}

[
  [ "Trailer (large)", "Large enclosed trailer" ],
  [ "Trailer (small)", "Small open trailer" ]
].each do |name, description|
  seed_resource(trailer_type, name: name, description: description, rates: trailer_rates)
end

# The development login bypass signs in as discourse_id 1.
alice = User.find_or_create_by!(discourse_id: 1) do |u|
  u.name = "Alice Admin"
  u.email = "alice@example.org"
  u.user_type = "resident"
  u.admin = true
end

bob = User.find_or_create_by!(discourse_id: 2) do |u|
  u.name = "Bob"
  u.email = "bob@example.org"
  u.user_type = "resident"
end

carol = User.find_or_create_by!(discourse_id: 3) do |u|
  u.name = "Carol"
  u.email = "carol@example.org"
  u.user_type = "resident"
end

dave = User.find_or_create_by!(discourse_id: 4) do |u|
  u.name = "Dave"
  u.email = "dave@example.org"
  u.user_type = "employee"
end

if Booking.count == 0
  today = Date.current
  cars = Resource.joins(:resource_type).where(resource_types: { name: "Car" }).order(:id)
  bikes = Resource.joins(:resource_type).where(resource_types: { name: "Bicycle" }).order(:id)
  trailer = Resource.joins(:resource_type).where(resource_types: { name: "Trailer" }).order(:id).first
  saturday = today.end_of_week(:monday) - 1.day

  [
    { user: alice, resource: cars.first, start_at: (today + 1.day).to_time.change(hour: 8),
      end_at: (today + 1.day).to_time.change(hour: 18), destination: "Hardware store" },
    { user: bob, resource: cars.second, start_at: today.to_time.change(hour: 9),
      end_at: (today + 2.days).to_time.change(hour: 17), destination: "Family visit" },
    { user: carol, resource: cars.third, start_at: today.to_time.change(hour: 7),
      end_at: today.to_time.change(hour: 20), destination: "Hospital" },
    { user: dave, resource: bikes.first, start_at: (today - 1.day).to_time.change(hour: 8),
      end_at: (today + 3.days).to_time.change(hour: 18) },
    { user: alice, resource: trailer, start_at: saturday.to_time.change(hour: 8),
      end_at: (saturday + 1.day).to_time.change(hour: 20) }
  ].each do |attrs|
    Booking.create!(attrs.merge(status: "active", creating_admin: true))
  end
end

puts "Seeded #{ResourceType.count} resource types, #{Resource.count} resources, #{User.count} users and #{Booking.count} bookings"
