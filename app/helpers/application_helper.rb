module ApplicationHelper
  RESOURCE_ICONS = {
    "car" => '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 16H9m10 0h3v-3.15a1 1 0 0 0-.84-.99L16 11l-2.7-3.6a1 1 0 0 0-.8-.4H5.24a2 2 0 0 0-1.8 1.1l-.8 1.63A6 6 0 0 0 2 12.42V16h2"/><circle cx="6.5" cy="16.5" r="2.5"/><circle cx="16.5" cy="16.5" r="2.5"/></svg>',
    "bicycle" => '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="5.5" cy="17.5" r="3.5"/><circle cx="18.5" cy="17.5" r="3.5"/><circle cx="15" cy="5" r="1"/><path d="M12 17.5V14l-3-3 4-3 2 3h2"/></svg>',
    "trailer" => '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="1" y="6" width="15" height="10" rx="1"/><circle cx="12" cy="16" r="2"/><path d="M16 11h5l3 5"/></svg>',
    "rocket-box" => '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="7" width="20" height="10" rx="2"/><path d="M12 7V4"/><path d="M7 7V5"/><path d="M17 7V5"/><line x1="2" y1="12" x2="22" y2="12"/></svg>',
    "toll" => '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="6" x2="12" y2="18"/><path d="M15 9.5a3 3 0 0 0-3-1.5 3 3 0 0 0 0 4h2a3 3 0 0 1 0 4 3 3 0 0 1-3-1.5"/></svg>'
  }.freeze

  # Grouped options for the booking destination select, from the admin-editable
  # list on the settings page (SiteSetting), falling back to the default.
  def destination_options
    SiteSetting.instance.destination_list.map do |group|
      [group["group"], Array(group["cities"]).map { |c| [c, c] }]
    end
  end

  def resource_icon(icon_name)
    RESOURCE_ICONS[icon_name]&.html_safe || ""
  end
end
