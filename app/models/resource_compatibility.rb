class ResourceCompatibility < ApplicationRecord
  belongs_to :resource
  belongs_to :accessory, class_name: "Resource"
end
