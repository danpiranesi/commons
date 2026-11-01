class BookingAccessory < ApplicationRecord
  belongs_to :booking
  belongs_to :accessory, class_name: "Resource"
end
