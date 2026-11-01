module RideshareHelper
  # Fallback map for environments where discourse_username hasn't been captured yet
  # (e.g. the dev bypass login). Real usernames come from the SSO payload and are
  # stored on the user; this is only used when that's blank.
  RIDESHARE_USERNAMES = {
    "alice@example.org" => "alice",
    "bob@example.org"   => "bob"
  }.freeze

  # The other member's Discourse username, from SSO or the demo fallback.
  def discourse_username_for(user)
    user&.discourse_username.presence || RIDESHARE_USERNAMES[user&.email&.downcase]
  end

  # A Discourse composer deep-link that opens a private message to `user`
  # pre-filled with title/body. Returns nil when we can't address them.
  def discourse_message_url(user, title:, body:)
    username = discourse_username_for(user)
    return unless username

    uri = URI("#{Rails.application.config.discourse_url}/new-message")
    uri.query = { username: username, title: title, body: body }.to_query
    uri.to_s
  end

  # Rideshare deep-link for a booking, or nil when the booking is the current
  # user's own or the owner can't be addressed.
  def rideshare_message_url(booking)
    target = booking.user
    return if target == current_user

    discourse_message_url(
      target,
      title: t("rideshare.message_title", resource: booking.resource.display_name),
      body:  t("rideshare.message_body",
               name: target.name,
               resource: booking.resource.display_name,
               date: booking.start_at.strftime("%-d. %B kl. %H:%M"))
    )
  end

  # Generic "message the member who had this car" deep-link (e.g. about tidying
  # up). nil when it's the current user or they can't be addressed.
  def contact_message_url(user, resource)
    return if user == current_user

    discourse_message_url(
      user,
      title: t("contact.message_title", resource: resource.display_name),
      body:  t("contact.message_body", name: user.name, resource: resource.display_name)
    )
  end
end
