require "test_helper"

# The rate rules are the money path, so they are checked against figures from
# a real monthly accounting sheet.
class BillingCategoryTest < ActiveSupport::TestCase
  setup { BillingCategory.seed_defaults! }

  def category(key) = BillingCategory.find_by!(key: key)

  test "normal rate leaves the calculated amount alone" do
    assert_equal 1805.50, category("member").charge_for(normal_amount: 1805.50, km: 951).to_f
    assert_equal 121.00,  category("hp").charge_for(normal_amount: 121.00, km: 0).to_f
  end

  test "double rate categories charge twice the normal amount" do
    assert_equal 3785.00, category("interessegruppe").charge_for(normal_amount: 1892.50, km: 0).to_f
    assert_equal 187.00,  category("interessegruppe").charge_for(normal_amount: 93.50, km: 0).to_f
    assert_equal 250.00,  category("interessegruppe").charge_for(normal_amount: 125.00, km: 0).to_f
    assert_equal 484.00,  category("servicegruppe").charge_for(normal_amount: 242.00, km: 0).to_f
    assert_equal 200.00,  category("ansat_lejer").charge_for(normal_amount: 100.00, km: 0).to_f
    assert_equal 200.00,  category("perma").charge_for(normal_amount: 100.00, km: 0).to_f
  end

  test "the state rate is per km and replaces the normal amount" do
    ks = category("ks_arbejdsgruppe")
    # 3,94 kr/km.
    assert_equal 1816.34, ks.charge_for(normal_amount: 611.00, km: 461).to_f
    assert_equal 2009.40, ks.charge_for(normal_amount: 594.00, km: 510).to_f
    assert_equal 866.80,  ks.charge_for(normal_amount: 319.00, km: 220).to_f
    assert_equal 126.08,  ks.charge_for(normal_amount: 79.50,  km: 32).to_f
  end

  test "changing the state rate changes what work groups pay" do
    ks = category("ks_arbejdsgruppe")
    ks.update!(rate_value: 4.10)
    assert_equal 410.00, ks.charge_for(normal_amount: 999.00, km: 100).to_f
  end

  test "only personal categories are offered for a person" do
    keys = BillingCategory.personal.pluck(:key)
    assert_includes keys, "member"
    assert_includes keys, "hp"
    assert_not_includes keys, "ks_arbejdsgruppe", "work groups are not a personal category"
    assert_not_includes keys, "interessegruppe"
  end

  test "reseeding does not overwrite a rate an admin has tuned" do
    ks = category("ks_arbejdsgruppe")
    ks.update!(rate_value: 4.25)
    BillingCategory.seed_defaults!
    assert_equal 4.25, ks.reload.rate_value.to_f
  end
end
