# Resource Types
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

# Sample resources
cars = [
  { name: "VW Transporter (AB 12 345)", description: "White 9-seater van" },
  { name: "Peugeot 308 (CD 67 890)", description: "Blue station wagon" },
  { name: "Toyota Yaris (EF 11 222)", description: "Red compact" },
  { name: "Skoda Octavia (GH 33 444)", description: "Silver estate" },
  { name: "Fiat Ducato (IJ 55 666)", description: "Large delivery van" },
]

cars.each do |attrs|
  resource = Resource.find_or_create_by!(name: attrs[:name]) do |r|
    r.resource_type = car_type
    r.description = attrs[:description]
    r.status = "active"
  end

  ResourcePrice.find_or_create_by!(resource: resource, user_type: "resident") do |rp|
    rp.day_rate = 150
    rp.km_rate = 0.50
    rp.base_fee = 25
  end

  ResourcePrice.find_or_create_by!(resource: resource, user_type: "employee") do |rp|
    rp.day_rate = 200
    rp.km_rate = 0.75
    rp.base_fee = 25
  end

  ResourceStat.find_or_create_by!(resource: resource) do |rs|
    rs.data = { "mileage" => rand(10_000..150_000) }
  end
end

bicycles = [
  { name: "El-cykel #1", description: "Electric cargo bike" },
  { name: "El-cykel #2", description: "Electric city bike" },
  { name: "Ladcykel", description: "Cargo bike (manual)" },
]

bicycles.each do |attrs|
  resource = Resource.find_or_create_by!(name: attrs[:name]) do |r|
    r.resource_type = bicycle_type
    r.description = attrs[:description]
    r.status = "active"
  end

  ResourcePrice.find_or_create_by!(resource: resource, user_type: "resident") do |rp|
    rp.day_rate = 50
    rp.km_rate = 0
    rp.base_fee = 0
  end

  ResourcePrice.find_or_create_by!(resource: resource, user_type: "employee") do |rp|
    rp.day_rate = 75
    rp.km_rate = 0
    rp.base_fee = 0
  end
end

trailers = [
  { name: "Trailer (stor)", description: "Large enclosed trailer" },
  { name: "Trailer (lille)", description: "Small open trailer" },
]

trailers.each do |attrs|
  resource = Resource.find_or_create_by!(name: attrs[:name]) do |r|
    r.resource_type = trailer_type
    r.description = attrs[:description]
    r.status = "active"
  end

  ResourcePrice.find_or_create_by!(resource: resource, user_type: "resident") do |rp|
    rp.day_rate = 100
    rp.km_rate = 0
    rp.base_fee = 0
  end

  ResourcePrice.find_or_create_by!(resource: resource, user_type: "employee") do |rp|
    rp.day_rate = 150
    rp.km_rate = 0
    rp.base_fee = 0
  end
end

# Dev user (matches the Discourse SSO dev bypass)
dev_user = User.find_or_create_by!(discourse_id: 1) do |u|
  u.name = "Alice Admin"
  u.email = "alice@example.org"
  u.user_type = "resident"
  u.admin = true
end

# Booking periods
BookingPeriod.find_or_create_by!(name: "Juni 2026") do |bp|
  bp.start_date = Date.new(2026, 6, 1)
  bp.end_date = Date.new(2026, 6, 30)
  bp.opens_at = Date.new(2026, 5, 25)
  bp.status = "open"
end

BookingPeriod.find_or_create_by!(name: "Juli 2026") do |bp|
  bp.start_date = Date.new(2026, 7, 1)
  bp.end_date = Date.new(2026, 7, 31)
  bp.opens_at = Date.new(2026, 6, 25)
  bp.status = "scheduled"
end

# Sample members
bob = User.find_or_create_by!(discourse_id: 2) do |u|
  u.name = "Bob"
  u.email = "bob@example.org"
  u.user_type = "resident"
  u.admin = true
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

# Sample bookings for this week
today = Date.current
period = BookingPeriod.find_by(status: "open")
all_cars = Resource.joins(:resource_type).where(resource_types: { name: "Car" })
all_bikes = Resource.joins(:resource_type).where(resource_types: { name: "Bicycle" })

if Booking.count == 0
  # First car tomorrow
  Booking.create!(
    user: dev_user,
    resource: all_cars.first,
    booking_period: period,
    start_at: (today + 1.day).to_time.change(hour: 8),
    end_at: (today + 1.day).to_time.change(hour: 18),
    status: "active"
  )

  # Second car for 3 days starting today
  Booking.create!(
    user: bob,
    resource: all_cars.second,
    booking_period: period,
    start_at: today.to_time.change(hour: 9),
    end_at: (today + 2.days).to_time.change(hour: 17),
    status: "active"
  )

  # Third car today
  Booking.create!(
    user: carol,
    resource: all_cars.third,
    booking_period: period,
    start_at: today.to_time.change(hour: 7),
    end_at: today.to_time.change(hour: 20),
    status: "active"
  )

  # A bike across this week
  Booking.create!(
    user: dave,
    resource: all_bikes.first,
    booking_period: period,
    start_at: (today - 1.day).to_time.change(hour: 8),
    end_at: (today + 3.days).to_time.change(hour: 18),
    status: "active"
  )

  # A trailer this weekend
  trailer = Resource.joins(:resource_type).where(resource_types: { name: "Trailer" }).first
  weekend_start = today.end_of_week(:monday) - 1.day # Saturday
  Booking.create!(
    user: dev_user,
    resource: trailer,
    booking_period: period,
    start_at: weekend_start.to_time.change(hour: 8),
    end_at: (weekend_start + 1.day).to_time.change(hour: 20),
    status: "active"
  )
end

puts "Seeded: #{ResourceType.count} resource types, #{Resource.count} resources, #{User.count} users, #{Booking.count} bookings, #{BookingPeriod.count} booking periods"
