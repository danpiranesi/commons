class PageHeaderComponent < ViewComponent::Base
  renders_one :actions

  def initialize(title:, subtitle: nil, breadcrumbs: nil)
    @title = title
    @subtitle = subtitle
    @breadcrumbs = breadcrumbs
  end

  erb_template <<~ERB
    <div class="mb-6">
      <% if @breadcrumbs&.any? %>
        <nav class="flex items-center gap-1.5 text-sm text-muted mb-2">
          <% @breadcrumbs.each_with_index do |(label, url), i| %>
            <% if i > 0 %><span class="text-[#c8c8c0]">/</span><% end %>
            <% if url %>
              <a href="<%= url %>" class="hover:text-foreground transition-colors"><%= label %></a>
            <% else %>
              <span class="text-foreground font-medium"><%= label %></span>
            <% end %>
          <% end %>
        </nav>
      <% end %>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 class="text-2xl font-medium"><%= @title %></h1>
          <% if @subtitle %>
            <p class="text-sm text-muted mt-1"><%= @subtitle %></p>
          <% end %>
        </div>
        <% if actions? %>
          <div class="flex flex-wrap items-center gap-2 sm:gap-3">
            <%= actions %>
          </div>
        <% end %>
      </div>
    </div>
  ERB
end
