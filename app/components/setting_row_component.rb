# One row in a settings section: label (with an optional info tooltip) and a short
# description on the left, the control on the right. Rows sit inside a
# `divide-y divide-card-border` container to read like a settings list.
#
#   <%= render(SettingRowComponent.new(label: "…", description: "…", tooltip: "…")) do |row| %>
#     <% row.with_control do %><input …><% end %>
#   <% end %>
#
# Pass stacked: true for wide controls (textareas, checkbox grids) so the control
# drops to a full-width row beneath the label instead of sitting to its right.
class SettingRowComponent < ViewComponent::Base
  renders_one :control

  def initialize(label:, description: nil, tooltip: nil, stacked: false)
    @label = label
    @description = description
    @tooltip = tooltip
    @stacked = stacked
  end

  erb_template <<~ERB
    <div class="px-5 py-4 <%= 'sm:flex sm:items-start sm:justify-between sm:gap-6' unless @stacked %>">
      <div class="min-w-0 <%= 'mb-3' if @stacked %>">
        <div class="flex items-center text-sm font-medium text-primary">
          <span><%= @label %></span>
          <% if @tooltip %><%= render(InfoTooltipComponent.new(text: @tooltip)) %><% end %>
        </div>
        <% if @description %>
          <p class="text-xs text-muted mt-1 max-w-md"><%= @description %></p>
        <% end %>
      </div>
      <div class="<%= @stacked ? 'w-full' : 'shrink-0 mt-3 sm:mt-0' %>">
        <%= control %>
      </div>
    </div>
  ERB
end
