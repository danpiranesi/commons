# Rideshare demo seed — idempotent.
# Creates a demo member if missing, then 3 upcoming car bookings owned by them.
# Run with: bin/rails runner db/seeds/rideshare_demo.rb

# ── 1. Ensure the demo member exists ────────────────────────────────────────
member = User.find_or_initialize_by(email: "bob@example.org")
if member.new_record?
  member.assign_attributes(
    discourse_id: 9999, # placeholder
    name:         "Bob",
    user_type:    "resident",
    admin:        false
  )
  member.save!
  puts "Created #{member.name} (id=#{member.id})"
else
  puts "#{member.name} already exists (id=#{member.id}, email=#{member.email})"
end

# ── 2. Pick the first active car resource ───────────────────────────────────
car = Resource
        .joins(:resource_type)
        .where(resource_types: { name: "Car" }, resources: { status: "active" })
        .order("resources.id")
        .first

abort "No active Car resource found — add one in the admin first." unless car
puts "Using car: #{car.display_name} (id=#{car.id})"

# ── 3. Create 3 non-overlapping bookings on upcoming days ───────────────────
slots = [
  { start_at: 2.days.from_now.change(hour: 8,  min: 0),
    end_at:   2.days.from_now.change(hour: 16, min: 0) },
  { start_at: 4.days.from_now.change(hour: 9,  min: 0),
    end_at:   4.days.from_now.change(hour: 17, min: 0) },
  { start_at: 6.days.from_now.change(hour: 8,  min: 0),
    end_at:   6.days.from_now.change(hour: 13, min: 0) }
]

slots.each_with_index do |slot, i|
  existing = Booking.find_by(user: member, resource: car, start_at: slot[:start_at])
  if existing
    puts "Slot #{i + 1} already exists (booking ##{existing.id}) — skipping."
    next
  end

  booking = Booking.new(
    user:        member,
    resource:    car,
    start_at:    slot[:start_at],
    end_at:      slot[:end_at],
    status:      "active",
    destination: "Town Centre" # required for mileage-tracking cars
  )

  if booking.save
    puts "Created booking ##{booking.id}: #{slot[:start_at].strftime('%-d %b %H:%M')} – #{slot[:end_at].strftime('%H:%M')}"
  else
    puts "Failed to create slot #{i + 1}: #{booking.errors.full_messages.join(', ')}"
  end
end

puts "\nDone. Log in as a different user and open one of #{member.name}'s bookings to see the rideshare button."
