# Demo mode turns a deployment into a public playground: every visitor is
# signed in as a fresh guest with admin rights, nothing is emailed, and the
# data is reset from the seeds every hour (see config/recurring.yml) and on boot.
Rails.application.config.demo_mode = ENV["DEMO_MODE"].present?

if Rails.application.config.demo_mode
  ActiveSupport.on_load(:action_mailer) { self.perform_deliveries = false }
end
