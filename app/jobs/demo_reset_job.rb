# Wipes everything visitors have done in demo mode and reloads the seeds.
class DemoResetJob < ApplicationJob
  queue_as :default

  def perform
    return unless Rails.application.config.demo_mode

    connection = ActiveRecord::Base.connection
    tables = connection.tables - %w[schema_migrations ar_internal_metadata]
    connection.truncate_tables(*tables)
    Rails.application.load_seed
  end
end
