# Single source of truth for how a resource is displayed as a card (title + two
# subtitle rows) everywhere in the app. Admins author a template per resource type
# on the design page; every context (admin index, calendar grid, mobile list)
# renders it through ResourceCardComponent so the same fields show the same way.
#
#   tpl = ResourceCardTemplate.new(resource)
#   tpl.title        # => "A-02 Blue Toyota"
#   tpl.subtitle1    # => "Alice Jensen"
#   tpl.subtitle2    # => "Carport 2"
class ResourceCardTemplate
  SLOTS = %w[title subtitle1 subtitle2].freeze

  # Whitelist of templatable fields → how to resolve each to a display string.
  # Both the editor palette and the renderer read from this one registry, so a
  # field can never be offered in the UI without a resolver, or vice versa.
  FIELDS = {
    "name"           => ->(r) { r.name },
    "port"           => ->(r) { r.port },
    "color"          => ->(r) { r.color },
    "make"           => ->(r) { r.make },
    "license_number" => ->(r) { r.license_number },
    "location"       => ->(r) { r.location },
    "regular_driver" => ->(r) { r.regular_driver },
    "description"    => ->(r) { r.description },
    "resource_type"  => ->(r) { r.resource_type&.name },
    "status"         => ->(r) { r.status&.humanize },
    "mileage"        => ->(r) { r.current_odometer.present? ? "#{r.current_odometer} km" : nil },
    "electric"       => ->(r) { r.electric? ? "⚡" : nil },
    "damage_notes"   => ->(r) { r.damage_notes.presence }
  }.freeze

  # Used when a resource type has no template of its own. display_name already
  # collapses to "port color make" for vehicles and "name" otherwise, so this
  # sensible default works for both cars and bikes out of the box.
  DEFAULT = {
    "title"     => { "fields" => %w[port color make], "separator" => " " },
    "subtitle1" => { "fields" => ["regular_driver"],  "separator" => " · " },
    "subtitle2" => { "fields" => ["location"],        "separator" => " · " }
  }.freeze

  # Resolve a single field to a non-blank string (or nil).
  def self.field_value(resource, key)
    FIELDS[key]&.call(resource).presence
  end

  # [[key, human label], …] for the editor's field picker.
  def self.available_fields
    FIELDS.keys.map { |key| [key, I18n.t("design.fields.#{key}")] }
  end

  # { field_key => resolved value } for one resource — feeds the editor's live
  # preview so the JS never needs to know how a field resolves.
  def self.sample_values(resource)
    FIELDS.keys.index_with { |key| field_value(resource, key).to_s }
  end

  # The stored template for a type, or the global default when unset. Always
  # returns a full, normalized structure so callers never guard for missing slots.
  def self.for(resource_type)
    stored = resource_type&.card_template
    return deep_dup(DEFAULT) if stored.blank?

    SLOTS.index_with do |slot|
      cfg = stored[slot] || DEFAULT[slot]
      {
        "fields"    => Array(cfg["fields"]).select { |k| FIELDS.key?(k) },
        "separator" => cfg["separator"].to_s
      }
    end
  end

  def self.deep_dup(hash)
    hash.transform_values { |v| v.is_a?(Hash) ? v.dup : v.dup }
  end

  def initialize(resource, template: nil)
    @resource = resource
    @template = template || self.class.for(resource.resource_type)
  end

  def title      = line("title")
  def subtitle1  = line("subtitle1")
  def subtitle2  = line("subtitle2")

  # Ordered field values for the slot, blanks dropped, joined by the separator
  # (defaulting to a single space so adjacent fields never collide).
  def line(slot)
    cfg = @template[slot] || {}
    separator = cfg["separator"].to_s
    separator = " " if separator.empty?
    values = Array(cfg["fields"]).filter_map { |key| self.class.field_value(@resource, key) }
    values.join(separator).presence
  end
end
