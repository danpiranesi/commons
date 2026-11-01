class User < ApplicationRecord
  USER_TYPES = %w[resident employee].freeze

  has_one :account, dependent: :destroy
  has_many :bookings, dependent: :restrict_with_error
  has_many :transactions, dependent: :restrict_with_error

  # Cars this member is the fast bruger (regular user) of.
  has_many :regular_for_resources, class_name: "Resource", foreign_key: :regular_user_id, dependent: :nullify

  # Fields the bookkeeper needs before this person can appear correctly on the
  # monthly sheet. Surfaced as a warning icon on the admin members list so a
  # newly created member's gaps are obvious.
  REQUIRED_ADMIN_FIELDS = {
    email:              ->(u) { u.email.present? },
    username:           ->(u) { u.username.present? },
    accounting_account: ->(u) { u.accounting_account.present? },
    accounting_name:    ->(u) { u.accounting_name.present? },
    billing_category:   ->(u) { u.billing_category_id.present? }
  }.freeze

  # Sort key for listing people by name the way a Danish reader expects: case
  # ignored, and æ, ø, å after z.
  def self.name_sort_key(name)
    name.to_s.strip.downcase.tr("äöéèáàüó", "æøeeaauo").tr("æøå", "{|}")
  end

  def name_sort_key = self.class.name_sort_key(name)

  def missing_admin_fields
    REQUIRED_ADMIN_FIELDS.reject { |_, present| present.call(self) }.keys
  end

  def missing_details? = missing_admin_fields.any?

  # Default working hours, keyed by cwday (1=Mon..7=Sun): the windows their
  # assigned car is held for them. Returns { start:, end: } (as "HH:MM") or nil.
  def working_hours_for(cwday)
    entry = (working_hours || {})[cwday.to_s]
    return nil unless entry.is_a?(Hash) && entry["start"].present? && entry["end"].present?
    entry
  end

  def working_hours?
    (working_hours || {}).values.any? { |e| e.is_a?(Hash) && e["start"].present? && e["end"].present? }
  end

  # What this person pays when booking for themselves. Assigned by an admin;
  # a booking made on behalf of a group is charged at the group's rate instead.
  belongs_to :billing_category, optional: true

  # Groups this person may book on behalf of.
  has_many :billing_group_memberships, dependent: :destroy
  has_many :billing_groups, through: :billing_group_memberships

  # Whether this person is in the member rate category — the people the community
  # taxes, and so the only ones a business charge can be deducted from.
  def member_category?
    billing_category&.key == "member"
  end

  # Personligt erhverv is only meaningful for a member, because the firm's
  # charge comes out of their salary. An admin can grant it anyway per person.
  def may_book_business?
    member_category? || business_override?
  end

  # What appears in the "on behalf of" dropdown. Admins may charge any group,
  # since they are the ones correcting mistakes at month end. Business groups are
  # filtered out for anyone who isn't eligible for them.
  def bookable_billing_groups
    scope = acting_admin? ? BillingGroup.active.ordered : billing_groups.merge(BillingGroup.active).order(:name)
    return scope if may_book_business?

    # Stays a relation so callers can keep chaining (.includes, etc.).
    scope.where.not(billing_category_id: BillingCategory.where(key: "personligt_erhverv").select(:id))
  end

  def may_book_for?(group)
    return true if group.nil?
    # A business charge is deducted from salary, so it stays closed to anyone the
    # community doesn't tax — admins included, unless the person is overridden.
    return false if group.billing_category&.key == "personligt_erhverv" && !may_book_business?

    acting_admin? || billing_group_ids.include?(group.id)
  end

  validates :discourse_id, uniqueness: true, allow_nil: true
  validates :name, presence: true
  validates :email, presence: true, uniqueness: true
  validates :user_type, presence: true, inclusion: { in: USER_TYPES }
  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }

  after_create :create_account!

  def resident?
    user_type == "resident"
  end

  def employee?
    user_type == "employee"
  end

  def booking_admin?
    acting_admin?
  end

  # Set on the signed-in user while an admin is previewing the member
  # experience. Lives in the session, never in the database, and only the
  # preview toggle sets it.
  attr_accessor :previewing_as_member

  # The admin flag as it should apply right now: false while previewing, so
  # every admin-only branch -- in the layout, the booking form, the "on behalf
  # of" list -- falls away together and the admin sees exactly what a member
  # sees. `admin?` itself stays the database truth, which is what the preview
  # toggle and the exit button check.
  def acting_admin?
    admin? && !previewing_as_member
  end

  # Whether this member should receive an emailed receipt when a trip is completed
  # or corrected. Opt-out is set in the member's own settings.
  def wants_receipt?
    !receipt_opt_out?
  end
end
