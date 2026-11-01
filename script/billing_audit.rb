# Read-only audit of completed trips, looking for suspicious charge patterns.
# Safe to run anywhere:
#
#   bin/rails runner script/billing_audit.rb
#
# Nothing is written. Each section names the trips a bookkeeper should re-check.
def money(v) = format("%.2f", v.to_f)
def line(b)  = "    ##{b.id} #{b.start_at.strftime('%Y-%m-%d')} #{b.resource.display_name} — #{b.user&.name}"

returned = Booking.where(status: "returned").includes(:user, :billing_group, resource: :resource_type)
puts "Completed trips: #{returned.count}"
puts

puts "1. Trips charged twice (more than one non-correction ledger entry)"
dupes = Transaction.where.not(booking_id: nil).group(:booking_id).having("COUNT(*) > 1").count
if dupes.empty?
  puts "    none"
else
  dupes.each do |booking_id, n|
    b = Booking.find(booking_id)
    txs = Transaction.where(booking_id: booking_id).order(:id)
    puts line(b) + " — #{n} entries totalling #{money(txs.sum(:amount))}"
    txs.each { |t| puts "        #{money(t.amount)}  #{t.description}" }
  end
  puts "    (a corrected trip legitimately has 2+; check the descriptions)"
end
puts

puts "2. Corrected trips whose stored rate no longer matches the charge"
puts "   (the stored rate is stale)"
suspect = returned.select do |b|
  r = b.billing_rate_struct
  r && b.total_amount && (r.charged.to_f - b.total_amount.to_f).abs > 0.01
end
if suspect.empty?
  puts "    none"
else
  suspect.each do |b|
    r = b.billing_rate_struct
    puts line(b)
    puts "        rate says charged #{money(r.charged)} (base #{money(r.base)} x#{r.value.to_f} #{r.mode})"
    puts "        booking says      #{money(b.total_amount)}   <-- difference #{money(b.total_amount - r.charged)}"
  end
end
puts

puts "3. Invoiced / group trips that nonetheless hit a personal ledger"
stray = returned.select { |b| !b.collected_via_ledger? && Transaction.exists?(booking_id: b.id) }
if stray.empty?
  puts "    none"
else
  stray.each do |b|
    puts line(b) + " — #{b.effective_billing_category&.name_da} (#{b.effective_billing_category&.collection})"
    Transaction.where(booking_id: b.id).each { |t| puts "        #{money(t.amount)}  #{t.description}" }
  end
end
puts

puts "4. Trips billed well past the window they booked (forgotten returns)"
late = returned.select do |b|
  booked = (b.end_at - b.start_at) / 3600.0
  booked.positive? && b.billed_hours > booked + 1
end
if late.empty?
  puts "    none"
else
  late.sort_by { |b| -(b.billed_hours - ((b.end_at - b.start_at) / 3600.0)) }.each do |b|
    booked = ((b.end_at - b.start_at) / 3600.0).round(1)
    puts line(b) + " — booked #{booked}h, billed #{b.billed_hours}h, charged #{money(b.total_amount)}"
  end
end
puts

puts "5. People whose price is doubled twice (user_type employee + a x2 category)"
stacked = User.includes(:billing_category).select do |u|
  u.user_type == "employee" && u.billing_category&.multiplier? && u.billing_category.rate_value.to_f != 1.0
end
if stacked.empty?
  puts "    none right now"
else
  stacked.each { |u| puts "    #{u.name} — #{u.billing_category.name_da} x#{u.billing_category.rate_value.to_f} on top of the employee 2x price" }
end
employees = User.where(user_type: "employee")
puts "    (#{employees.count} people are user_type=employee and already pay 2x the resident price:"
puts "     #{employees.pluck(:name).join(', ')})" if employees.any?
puts

puts "6. Which column of the monthly sheet each resource type reports in"
ResourceType.order(:sort_order, :name).each do |rt|
  column = rt.billed_as_car? ? "BILER " : "CYKLER"
  billed = returned.select { |b| b.resource.resource_type_id == rt.id }
  next if billed.empty? && Resource.where(resource_type: rt).none?
  puts "    #{column}  #{rt.name.to_s.ljust(14)} #{billed.size} billed trips, #{money(billed.sum { |b| b.total_amount || 0 })} kr"
end
puts "    (a trailer, rocket box or bridge toll is a car cost — it must not land in CYKLER)"
puts

puts "7. Trips by people with no billing category (charged at plain rate, bank transfer)"
uncat = returned.select { |b| b.billing_group_id.nil? && b.user&.billing_category_id.nil? }
puts "    #{uncat.count} trips across #{uncat.map(&:user_id).uniq.count} people"
