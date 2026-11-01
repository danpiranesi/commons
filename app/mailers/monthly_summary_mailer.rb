# The month-end summary the bookkeeper works from. Sent on the 10th for the
# previous month, with the kørsel workbook attached so corrections can be made
# before the month is closed.
class MonthlySummaryMailer < ApplicationMailer
  def summary(billing_month, recipients)
    @billing_month = billing_month
    @sheet   = MonthlyKoerselSheet.new(billing_month)
    @closed  = ClosedBillingMonth.closed?(billing_month)
    @trips   = Booking.where(status: "returned", billing_month: billing_month).count

    attachments["koersel_#{billing_month}.xlsx"] = MonthlyKoerselXlsx.new(@sheet).render

    mail(to: recipients, subject: "Kørsel #{@sheet.month_label} — månedsoversigt")
  end
end
