# Takes a completed trip off the bill entirely — for when the member should not
# pay for it at all: the car broke down, the key was missing, the trip never
# really happened. Admin-only, from the monthly billing screen.
#
# Nothing is erased. The ledger is immutable, so whatever this trip has posted
# to the member's account is offset by a refund, and the booking is marked
# cancelled. Every billing report reads only returned trips, so it drops out of
# the overview, the bank CSV and the kørsel sheet in one move.
#
#   ReservationWaiverService.call(booking:, waived_by:, reason: "Bilen startede ikke")
class ReservationWaiverService
  Result = Data.define(:success, :refunded, :error) do
    def success? = success
  end

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(booking:, waived_by:, reason: nil)
    @booking   = booking
    @waived_by = waived_by
    @reason    = reason.presence
  end

  def call
    return failure(:not_returned) unless @booking.status == "returned"
    if @booking.billing_month.present? && ClosedBillingMonth.closed?(@booking.billing_month)
      return failure(:month_closed)
    end

    refunded = nil
    ActiveRecord::Base.transaction do
      # Re-read under a row lock so a double-click cannot refund twice.
      @booking.lock!
      raise ActiveRecord::Rollback unless @booking.status == "returned"

      refunded = 0
      # Net what this trip has cost the member so far (the charge plus any
      # corrections), and post the opposite. Invoiced people and groups have no
      # ledger entries, so there is nothing to refund for them.
      net = Transaction.where(booking_id: @booking.id).sum(:amount)
      unless net.zero?
        account = @booking.user.account || @booking.user.create_account!
        account.transactions.create!(
          user:        @booking.user,
          amount:      -net,
          description: "#{@booking.resource.display_name} — #{I18n.t('receipts.waiver.ledger', date: @booking.start_at.to_date)}",
          booking:     @booking,
          created_by:  @waived_by
        )
        refunded = -net
      end

      @booking.update!(
        status: "cancelled",
        total_amount: 0,
        cancellation_reason: @reason || I18n.t("receipts.waiver.default_reason", name: @waived_by&.name)
      )
    end

    return failure(:not_returned) if refunded.nil?

    Result.new(success: true, refunded: refunded, error: nil)
  rescue ActiveRecord::RecordInvalid
    failure(:persist_failed)
  end

  private

  def failure(error)
    Result.new(success: false, refunded: 0, error: error)
  end
end
