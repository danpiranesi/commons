class ApplicationMailer < ActionMailer::Base
  # Must match the authenticated SMTP mailbox, or the provider rejects it.
  default from: "Commons Booking <discourse@example.org>"
  layout "mailer"
end
