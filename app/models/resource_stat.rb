class ResourceStat < ApplicationRecord
  belongs_to :resource

  def mileage
    data&.dig("mileage")
  end

  def mileage=(value)
    self.data = (data || {}).merge("mileage" => value)
  end
end
