namespace :demo do
  desc "Reset the demo data (only does anything when DEMO_MODE is set)"
  task reset: :environment do
    abort "DEMO_MODE is not set; refusing to wipe the database" unless Rails.application.config.demo_mode
    DemoResetJob.perform_now
    puts "Demo data reset"
  end
end
