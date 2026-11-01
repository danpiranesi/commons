class AddInheritRulesFromCarToResourceTypes < ActiveRecord::Migration[8.1]
  # Accessories attached to a car (trailers, roof boxes, tolls) follow the car's
  # lifecycle rules. BookingRules.for resolves the inheritance.
  def up
    add_column :resource_types, :inherit_rules_from_car, :boolean, null: false, default: false
    execute "UPDATE resource_types SET inherit_rules_from_car = true WHERE name IN ('Trailer', 'Rocket Box', 'Toll')"
  end

  def down
    remove_column :resource_types, :inherit_rules_from_car
  end
end
