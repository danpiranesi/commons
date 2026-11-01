class ReceiptMailer < ApplicationMailer
  def completion(booking)
    assign_receipt(booking)
    mail(to: booking.user.email, subject: "Kvittering — #{@resource.display_name}")
  end

  # Sent after an admin corrects a trip; worded as a correction, not a new charge.
  def correction(booking)
    assign_receipt(booking)
    mail(to: booking.user.email, subject: "Rettet kvittering — #{@resource.display_name}")
  end

  private

  # Prefer the breakdown stored at completion, so the line items always sum to
  # what was charged. Bookings without a stored breakdown fall back to a recompute.
  def assign_receipt(booking)
    @booking  = booking
    @resource = booking.resource
    @rate     = booking.billing_rate_struct

    # Show the billed (rounded) period rather than the booked one, so a late
    # return's charge doesn't read as the wrong hourly rate.
    @period_end = booking.completed_at ? booking.billed_until_time : booking.end_at
    @returned_off_booking = booking.completed_at.present? &&
                            @period_end.change(sec: 0) != booking.end_at.change(sec: 0)

    @breakdown = booking.charge_breakdown_struct || PricingCalculator.new(
      booking, start_odometer: booking.start_mileage, ending_reading: booking.end_mileage
    ).breakdown

    @base   = @breakdown.total                  # before the rate was applied
    @amount = booking.total_amount || @base     # what was actually charged
    @billed_to_group = booking.on_behalf_of_group? ? booking.billing_group&.name : nil
  end
end
