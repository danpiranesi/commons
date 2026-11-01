# Rewrites the private-destination marker to the neutral wording. The strings are
# inlined rather than read from Booking so the migration keeps working if those
# constants change.
class RenamePrivateDestinationMarker < ActiveRecord::Migration[8.1]
  OLD_MARKERS = ["Ikke din sag", "None of your business"].freeze
  NEW_MARKER  = "Privat".freeze

  def up
    execute <<~SQL.squish
      UPDATE bookings
         SET destination = #{connection.quote(NEW_MARKER)}
       WHERE destination IN (#{OLD_MARKERS.map { |m| connection.quote(m) }.join(", ")})
    SQL
  end

  def down
    # Irreversible by design.
  end
end
