# Mails the previous month's kørsel summary to the admins who do the bookkeeping.
# Scheduled for the 10th (see config/recurring.yml), which leaves time to correct
# the month before it is closed.
class MonthlySummaryJob < ApplicationJob
  queue_as :default

  def perform(billing_month = nil)
    billing_month ||= (Date.current << 1).strftime("%Y%m")

    recipients = User.where(admin: true).where.not(email: [nil, ""]).pluck(:email)
    return if recipients.empty?

    MonthlySummaryMailer.summary(billing_month, recipients).deliver_now
  end
end
