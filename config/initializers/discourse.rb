# Discourse SSO configuration
Rails.application.config.discourse_url = ENV.fetch("DISCOURSE_BASE_URL", "https://forum.example.org")
Rails.application.config.booking_base_url = ENV.fetch("BOOKING_BASE_URL", "http://localhost:3000")

# Bypass SSO and auto-login as the dev user when no secret is configured.
Rails.application.config.discourse_dev_bypass = ENV["DISCOURSE_CONNECT_PROVIDER_SECRET"].blank?
