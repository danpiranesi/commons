class AddCardTemplateToResourceTypes < ActiveRecord::Migration[8.1]
  def change
    # Which resource fields compose a card's title and subtitle rows. Empty {}
    # means ResourceCardTemplate::DEFAULT.
    add_column :resource_types, :card_template, :jsonb, default: {}, null: false
  end
end
