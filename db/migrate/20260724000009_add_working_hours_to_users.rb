class AddWorkingHoursToUsers < ActiveRecord::Migration[8.1]
  # A regular user's working hours, keyed by cwday (1=Mon..7=Sun):
  #   { "1" => { "start" => "08:00", "end" => "16:00" }, ... }
  # Their assigned car is held for them during these windows (see Resource#held_for?).
  def change
    add_column :users, :working_hours, :jsonb
  end
end
