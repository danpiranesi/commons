# Controls which fields appear on the booking detail page (bookings#show),
# per resource type. Admins configure the ordered field list in the Design editor.
#
#   tpl = BookingDetailTemplate.for(resource_type)
#   tpl.show?("rideshare")  # => true / false
class BookingDetailTemplate
  FIELDS = {
    "destination" => :destination_label,
    "rideshare"   => :rideshare_label,
    "duration"    => :duration_label,
    "notes"       => :notes_label,
    "accessories" => :accessories_label,
    "cost"        => :cost_label
  }.freeze

  DEFAULT_FIELDS = FIELDS.keys.freeze

  def self.for(resource_type)
    stored = resource_type&.booking_template
    if stored.blank? || stored["fields"].blank?
      new(DEFAULT_FIELDS.dup)
    else
      new(Array(stored["fields"]).select { |k| FIELDS.key?(k) })
    end
  end

  def self.available_fields
    FIELDS.keys.map { |key| [key, I18n.t("design.booking_fields.#{key}")] }
  end

  def initialize(fields)
    @fields = fields
  end

  attr_reader :fields

  def show?(key)
    @fields.include?(key.to_s)
  end
end
