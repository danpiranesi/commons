# Applies a billing category to a base charge and describes what it did, so the
# member sees the same rate in the estimate, on the receipt, and on the monthly
# sheet. The transform is BillingCategory#charge_for, so a booking's charge and
# the sheet can never disagree.
#
#   normal      charged = base                  (uncategorised, or a x1 category)
#   multiplier  charged = base x value          (e.g. double rate)
#   per_km      charged = km x value            (the state rate; base is ignored)
BillingRate = Struct.new(:mode, :value, :category_name, :base, :km, :charged, keyword_init: true) do
  def self.apply(category:, base_total:, km: 0)
    base = base_total.to_d
    distance = km.to_i

    if category.nil? || (category.multiplier? && category.rate_value.to_f == 1.0)
      new(mode: "normal", value: BigDecimal("1"), category_name: category&.name_da,
          base: base, km: distance, charged: base)
    else
      new(mode: category.rate_mode, value: category.rate_value.to_d, category_name: category.name_da,
          base: base, km: distance, charged: category.charge_for(normal_amount: base, km: distance))
    end
  end

  # Rebuild from what was frozen on the booking at completion, so a later change
  # to the category's rate never rewrites an already-issued receipt.
  def self.from_stored(hash)
    return nil if hash.blank?
    new(mode: hash["mode"], value: BigDecimal(hash["value"].to_s), category_name: hash["category"],
        base: BigDecimal(hash["base"].to_s), km: hash["km"].to_i,
        charged: BigDecimal(hash["charged"].to_s))
  end

  # Re-apply this frozen rate to a recomputed base. Corrections use this rather
  # than the category's current rate, so a later rate change never rewrites an
  # issued receipt.
  def reapply(base_total:, km:)
    base_d     = base_total.to_d
    distance   = km.to_i
    new_charge = per_km? ? (distance * value).round(2) : (base_d * value).round(2)

    self.class.new(mode: mode, value: value, category_name: category_name,
                   base: base_d, km: distance, charged: new_charge)
  end

  def for_storage
    { "mode" => mode, "value" => value.to_s, "category" => category_name,
      "base" => base.to_s, "km" => km, "charged" => charged.to_s }
  end

  def adjusted?    = mode != "normal"
  def multiplier?  = mode == "multiplier"
  def per_km?      = mode == "per_km"
end
