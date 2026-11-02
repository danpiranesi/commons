# Discourse SSO configuration
Rails.application.config.discourse_url = ENV.fetch("DISCOURSE_BASE_URL", "https://forum.example.org")
Rails.application.config.booking_base_url = ENV.fetch("BOOKING_BASE_URL") { ENV.fetch("RENDER_EXTERNAL_URL", "http://localhost:3000") }

# In development and test, skip SSO and sign in as a local admin when no secret is configured.
Rails.application.config.discourse_dev_bypass = Rails.env.local? && ENV["DISCOURSE_CONNECT_PROVIDER_SECRET"].blank?
