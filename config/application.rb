require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Commons
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.session_store :cookie_store, key: "_commons_session"

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.i18n.default_locale = :da
    config.i18n.available_locales = [:da, :en]
    config.i18n.fallbacks = true
    # Display and interpret wall-clock times in Copenhagen; the DB stores UTC.
    config.time_zone = "Europe/Copenhagen"
    # No uploads are resized anywhere, so skip the image processing dependency.
    config.active_storage.variant_processor = :disabled
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
