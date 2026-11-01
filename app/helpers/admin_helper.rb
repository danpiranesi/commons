module AdminHelper
  NAV_ICONS = {
    "grid" => '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/></svg>',
    "layers" => '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="12 2 2 7 12 12 22 7 12 2"/><polyline points="2 17 12 22 22 17"/><polyline points="2 12 12 17 22 12"/></svg>',
    "calendar" => '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>',
    "arrow-left" => '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="19" y1="12" x2="5" y2="12"/><polyline points="12 19 5 12 12 5"/></svg>',
    "users" => '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>'
  }.freeze

  def admin_nav_link(label, path, icon: nil)
    active = path == "/" ? request.path == "/" : request.path.start_with?(path)
    css = "flex items-center gap-2.5 px-4 py-2 text-sm transition-colors #{active ? 'bg-sage/10 text-sage font-medium' : 'text-primary hover:bg-hover'}"

    link_to path, class: css do
      safe_join([
        icon ? NAV_ICONS[icon]&.html_safe : nil,
        label
      ].compact)
    end
  end

  def status_variant(status)
    case status
    when "active" then :success
    when "unavailable" then :warning
    when "retired" then :default
    else :default
    end
  end

  def billing_type_label(billing_type)
    case billing_type
    when "per_day_and_km" then t("billing_types.per_day_and_km")
    when "per_day" then t("billing_types.per_day")
    when "free" then t("billing_types.free")
    else billing_type
    end
  end
end
