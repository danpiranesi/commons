require "csv"

# Imports members from a Discourse user export so their accounts exist in the
# booking system before they ever log in — letting the bookkeeper fill in konto,
# username and rate category ahead of time.
#
# Get the CSV from the forum: Admin -> Users -> Export. It carries at least
# id, name, username, email and group_names.
#
#   bin/rails forum:import[tmp/discourse_users.csv]              # dry run, changes nothing
#   COMMIT=1 bin/rails forum:import[tmp/discourse_users.csv]     # actually writes
#   GROUPS="members,beboere" bin/rails forum:import[...]     # override group filter
#
# Safe to re-run: users are matched on discourse_id (falling back to email), and
# fields an admin curates (konto, accounting name, rate category, working hours)
# are never overwritten on someone who already exists.
namespace :forum do
  desc "Import members from a Discourse user export CSV (dry run unless COMMIT=1)"
  task :import, [:path] => :environment do |_t, args|
    path = args[:path] or abort "Usage: bin/rails forum:import[path/to/export.csv]"
    abort "No such file: #{path}" unless File.exist?(path)

    commit  = ENV["COMMIT"] == "1"
    groups  = (ENV["GROUPS"] || "member,members,beboer,beboere,residents").downcase.split(",").map(&:strip)
    exclude = (ENV["EXCLUDE_GROUPS"] || "volunteers").downcase.split(",").map(&:strip)

    rows = CSV.read(path, headers: true)
    puts "Read #{rows.size} rows from #{path}"
    puts "Including groups: #{groups.join(', ')} | excluding: #{exclude.join(', ')}"
    puts commit ? "MODE: COMMIT (writing)" : "MODE: DRY RUN (nothing will be written)"
    puts

    member_category = BillingCategory.find_by(key: "member")
    created = updated = skipped_group = skipped_invalid = 0
    problems = []

    rows.each do |row|
      email = row["email"].to_s.strip.downcase
      name  = row["name"].to_s.strip.presence || row["username"].to_s.strip
      uname = row["username"].to_s.strip
      did   = row["id"].to_s.strip

      if email.blank? || did.blank?
        skipped_invalid += 1
        problems << "row missing id/email: #{row.to_h.slice('id', 'username', 'email')}"
        next
      end

      # group_names is a comma/semicolon separated list on the Discourse export.
      member_of = row["group_names"].to_s.downcase.split(/[,;]/).map(&:strip)
      next (skipped_group += 1) if (member_of & exclude).any?
      # When the export has no group column at all, take every row; otherwise
      # only the groups asked for.
      if row.headers.include?("group_names") && (member_of & groups).empty?
        skipped_group += 1
        next
      end

      user = User.find_by(discourse_id: did) || User.find_by(email: email)

      if user.nil?
        created += 1
        puts "  CREATE  #{name} <#{email}> (@#{uname})"
        next unless commit

        User.create!(
          discourse_id: did, email: email, name: name,
          discourse_username: uname, username: uname,
          user_type: "resident", billing_category: member_category
        )
      else
        # Only fill blanks — never clobber what an admin has already curated.
        changes = {}
        changes[:discourse_id]       = did   if user.discourse_id.blank?
        changes[:email]              = email if user.email.blank?
        changes[:name]               = name  if user.name.blank?
        changes[:discourse_username] = uname if user.discourse_username.blank?
        changes[:username]           = uname if user.username.blank?
        changes[:billing_category]   = member_category if user.billing_category_id.blank? && member_category

        next if changes.empty?

        updated += 1
        puts "  UPDATE  #{user.name} <#{user.email}> -> #{changes.keys.join(', ')}"
        user.update!(changes) if commit
      end
    end

    puts
    puts "created: #{created}  updated: #{updated}  skipped (group): #{skipped_group}  skipped (invalid): #{skipped_invalid}"
    problems.first(10).each { |p| puts "  ! #{p}" }
    puts "\nDry run — re-run with COMMIT=1 to apply." unless commit
  end
end
