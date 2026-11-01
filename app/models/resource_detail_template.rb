# Controls which fields appear on the public resource detail page (resources#show),
# per resource type. Admins configure the ordered field list in the Design editor;
# the view calls show?(key) on each section and skips it when false.
#
#   tpl = ResourceDetailTemplate.for(resource_type)
#   tpl.show?("license_number")  # => true / false
#   tpl.fields                   # => ["status", "vehicle", ...]  ordered
class ResourceDetailTemplate
  # All fields the admin can toggle. Order here defines the palette order.
  FIELDS = {
    "status"         => :status_label,
    "vehicle"        => :vehicle_label,
    "license_number" => :license_number_label,
    "location"       => :location_label,
    "description"    => :description_label,
    "damage_notes"   => :damage_notes_label,
    "regular_driver" => :regular_driver_label,
    "mileage"        => :mileage_label,
    "accessories"    => :accessories_label
  }.freeze

  # Shown when a resource type has no stored template.
  DEFAULT_FIELDS = FIELDS.keys.freeze

  def self.for(resource_type)
    stored = resource_type&.detail_template
    if stored.blank? || stored["fields"].blank?
      new(DEFAULT_FIELDS.dup)
    else
      new(Array(stored["fields"]).select { |k| FIELDS.key?(k) })
    end
  end

  def self.available_fields
    FIELDS.keys.map { |key| [key, I18n.t("design.detail_fields.#{key}")] }
  end

  def initialize(fields)
    @fields = fields
  end

  attr_reader :fields

  def show?(key)
    @fields.include?(key.to_s)
  end
end
