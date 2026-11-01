module AdminNavHelper
  # The admin area is organised into a handful of top-level sections, each of
  # which opens a page carrying a tab bar for its sub-pages. Keeping the shape
  # here (rather than hard-coded in the layout) means the sidebar and the tab
  # bar always agree on which section is active.
  #
  # Each tab lists the controllers that "belong" to it, so member/edit pages
  # (e.g. editing a booking, printing a label sheet) still light up the right
  # section even though they aren't tabs themselves.
  def admin_sections
    [
      { key: "resources", label: t("admin.nav.resources_section"), icon: "grid", tabs: [
        admin_tab(:all_resources,      admin_resources_path,           %w[admin/resources admin/label_sheets]),
        admin_tab(:resource_types,     admin_resource_types_path,      %w[admin/resource_types]),
        admin_tab(:design,             admin_design_path,              %w[admin/design])
      ] },
      { key: "billing", label: t("admin.nav.billing_section"), icon: "calendar", tabs: [
        admin_tab(:monthly_overview,   admin_monthly_overview_path,    %w[admin/monthly_overview admin/bookings]),
        admin_tab(:billing_categories, admin_billing_categories_path,  %w[admin/billing_categories]),
        admin_tab(:billing_groups,     admin_billing_groups_path,      %w[admin/billing_groups])
      ] },
      { key: "members", label: t("admin.nav.users"), icon: "users", tabs: [
        admin_tab(:users,              admin_users_path,               %w[admin/users])
      ] },
      { key: "settings", label: t("admin.nav.settings_section"), icon: "layers", tabs: [
        admin_tab(:settings_general,   admin_homepage_header_path,     %w[admin/site_settings]),
        admin_tab(:rules,              admin_rules_path,               %w[admin/rules])
      ] }
    ]
  end

  # The section the current page lives in, or nil for pages outside the grouped
  # nav (which simply leaves the sidebar unhighlighted).
  def active_admin_section
    admin_sections.find { |section| admin_section_active?(section) }
  end

  def admin_section_active?(section)
    section[:tabs].any? { |tab| tab[:controllers].include?(controller_path) }
  end

  def admin_tab_active?(tab)
    tab[:controllers].include?(controller_path)
  end

  # Sidebar entry for a whole section, linking to its first tab.
  def admin_section_link(section)
    active = admin_section_active?(section)
    css = "flex items-center gap-2.5 px-4 py-2 text-sm transition-colors #{active ? 'bg-sage/10 text-sage font-medium' : 'text-primary hover:bg-hover'}"
    link_to section[:tabs].first[:path], class: css do
      safe_join([AdminHelper::NAV_ICONS[section[:icon]]&.html_safe, section[:label]].compact)
    end
  end

  private

  def admin_tab(key, path, controllers)
    { key: key.to_s, label: t("admin.nav.#{key}"), path: path, controllers: controllers }
  end
end
