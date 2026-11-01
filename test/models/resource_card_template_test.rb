require "test_helper"

class ResourceCardTemplateTest < ActiveSupport::TestCase
  def car_type(template: {})
    ResourceType.create!(name: "Car-#{SecureRandom.hex(3)}", billing_type: "per_day_and_km",
                         sort_order: 1, card_template: template)
  end

  def car(type, **attrs)
    Resource.create!({ name: "VW", status: "active", resource_type: type,
                       port: "A-02", color: "Blue", make: "Toyota",
                       location: "Carport 2", regular_driver: "Anna" }.merge(attrs))
  end

  test "falls back to the global default when the type has no template" do
    tpl = ResourceCardTemplate.new(car(car_type))
    assert_equal "A-02 Blue Toyota", tpl.title      # display_name for a vehicle
    assert_equal "Anna", tpl.subtitle1              # regular_driver
    assert_equal "Carport 2", tpl.subtitle2         # location
  end

  test "composes fields in order joined by the slot separator" do
    type = car_type(template: {
      "title"     => { "fields" => %w[port color make], "separator" => " " },
      "subtitle1" => { "fields" => %w[regular_driver], "separator" => " · " },
      "subtitle2" => { "fields" => %w[location status], "separator" => " · " }
    })
    tpl = ResourceCardTemplate.new(car(type))
    assert_equal "A-02 Blue Toyota", tpl.title
    assert_equal "Carport 2 · Active", tpl.subtitle2
  end

  test "drops blank fields so separators never dangle" do
    type = car_type(template: {
      "title"     => { "fields" => %w[port color make], "separator" => " " },
      "subtitle1" => { "fields" => %w[regular_driver], "separator" => " · " },
      "subtitle2" => { "fields" => %w[location], "separator" => " · " }
    })
    # make is blank → title collapses, no double space
    tpl = ResourceCardTemplate.new(car(type, make: nil, color: nil))
    assert_equal "A-02", tpl.title
  end

  test "an empty slot resolves to nil, not an empty string" do
    type = car_type(template: {
      "title"     => { "fields" => %w[display_name], "separator" => " " },
      "subtitle1" => { "fields" => [], "separator" => " " },
      "subtitle2" => { "fields" => [], "separator" => " " }
    })
    tpl = ResourceCardTemplate.new(car(type))
    assert_nil tpl.subtitle1
  end

  test "available_fields exposes every registered field with a label" do
    assert_equal ResourceCardTemplate::FIELDS.size, ResourceCardTemplate.available_fields.size
    ResourceCardTemplate.available_fields.each { |key, label| assert label.present?, "missing label for #{key}" }
  end
end
