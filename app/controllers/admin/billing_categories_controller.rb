module Admin
  # Rates per category. Set once here rather than per person, so nobody can end
  # up on last year's state rate or a different multiplier to their neighbour.
  class BillingCategoriesController < BaseController
    def index
      BillingCategory.seed_defaults! if BillingCategory.none?
      ResourceType.seed_default_rates!
      @categories     = BillingCategory.ordered
      @resource_types = ResourceType.priceable
    end

    # Everything on the page is saved together: category multipliers, how each is
    # collected, and the default hourly rates.
    def update_all
      updated = 0

      (params[:rates] || {}).each do |id, value|
        category = BillingCategory.find_by(id: id)
        next if category.nil? || value.blank?
        collection = params.dig(:collection, id)
        category.rate_value = value.to_s.tr(",", ".").to_f
        category.collection = collection if BillingCategory::COLLECTIONS.include?(collection)
        category.save!
        updated += 1
      end

      (params[:default_rates] || {}).each do |type_id, by_user_type|
        type = ResourceType.find_by(id: type_id)
        next unless type
        rates = type.default_hour_rates || {}
        by_user_type.each do |user_type, value|
          next unless User::USER_TYPES.include?(user_type)
          rates[user_type] = value.to_s.tr(",", ".").to_f.to_s if value.present?
        end
        type.update!(default_hour_rates: rates)
      end

      redirect_to admin_billing_categories_path,
                  notice: t("admin.billing_categories.saved", count: updated)
    end
  end
end
