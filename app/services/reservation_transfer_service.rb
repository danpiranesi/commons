# Moves a completed trip to whoever should really pay for it — another member,
# or a work group — after it has been billed, e.g. a trip booked under the
# wrong person.
#
# The ledger is immutable, so nothing is edited: whatever the trip has cost its
# current payer is refunded, the trip is re-priced for the new payer (their own
# prices and rate category, exactly as at completion), and the new charge is
# posted to the new payer's account if they settle through the personal ledger.
# Groups and invoiced people are billed on the monthly sheet and get no entry.
#
#   ReservationTransferService.call(booking:, user:, billing_group:, transferred_by:)
#   (billing_group: nil means the member pays for it themselves)
class ReservationTransferService
  Result = Data.define(:success, :new_amount, :error) do
    def success? = success
  end

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(booking:, user:, billing_group:, transferred_by:)
    @booking        = booking
    @user           = user
    @billing_group  = billing_group
    @transferred_by = transferred_by
  end

  def call
    return failure(:not_completed) unless @booking.status == "returned"
    if @booking.billing_month.present? && ClosedBillingMonth.closed?(@booking.billing_month)
      return failure(:month_closed)
    end
    return failure(:nothing_to_transfer) if @user == @booking.user && @billing_group == @booking.billing_group

    new_amount = nil
    ActiveRecord::Base.transaction do
      @booking.lock!

      refund_current_payer!

      @booking.user          = @user
      @booking.billing_group = @billing_group
      # An admin may put a trip on any group, member of it or not — they are the
      # ones sorting out who pays.
      @booking.group_set_by_admin = true

      breakdown = PricingCalculator.new(
        @booking, start_odometer: @booking.start_mileage, ending_reading: @booking.end_mileage
      ).breakdown
      rate = @booking.billing_rate_for(base_total: breakdown.total, km: @booking.km_driven.to_i)
      new_amount = rate.charged

      @booking.update!(
        total_amount:     new_amount,
        charge_breakdown: ReservationCompletionService.breakdown_hash(breakdown),
        billing_rate:     rate.for_storage
      )

      charge_new_payer!(new_amount) if @booking.collected_via_ledger?
    end

    ReceiptMailer.correction(@booking).deliver_later if @booking.user&.wants_receipt?
    Result.new(success: true, new_amount: new_amount, error: nil)
  rescue ActiveRecord::RecordInvalid
    failure(:persist_failed)
  end

  private

  # Net out every entry this trip has posted, per account, so a trip already
  # corrected (or moved before) is refunded to exactly who paid what.
  def refund_current_payer!
    Transaction.where(booking_id: @booking.id).group(:account_id, :user_id).sum(:amount).each do |(account_id, user_id), net|
      next if net.zero?

      Transaction.create!(
        account_id: account_id, user_id: user_id, amount: -net, booking: @booking,
        created_by: @transferred_by, description: description("transfer_out")
      )
    end
  end

  def charge_new_payer!(amount)
    return if amount.zero?

    account = @user.account || @user.create_account!
    account.transactions.create!(
      user: @user, amount: -amount, booking: @booking,
      created_by: @transferred_by, description: description("transfer_in")
    )
  end

  def description(key)
    "#{@booking.resource.display_name} — #{I18n.t("receipts.transfer.#{key}", date: @booking.start_at.to_date)}"
  end

  def failure(error)
    Result.new(success: false, new_amount: nil, error: error)
  end
end
