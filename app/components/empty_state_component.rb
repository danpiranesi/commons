class EmptyStateComponent < ViewComponent::Base
  def initialize(title:, description: nil, icon: nil)
    @title = title
    @description = description
    @icon = icon
  end

  erb_template <<~ERB
    <div class="text-center py-12">
      <% if @icon %>
        <div class="text-muted mb-3"><%= @icon %></div>
      <% end %>
      <h3 class="text-sm font-medium text-primary mb-1"><%= @title %></h3>
      <% if @description %>
        <p class="text-sm text-muted"><%= @description %></p>
      <% end %>
      <% if content.present? %>
        <div class="mt-4"><%= content %></div>
      <% end %>
    </div>
  ERB
end
