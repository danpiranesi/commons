class CardComponent < ViewComponent::Base
  renders_one :header
  renders_one :footer

  def initialize(padding: true, **html_attrs)
    @padding = padding
    @html_attrs = html_attrs
  end

  erb_template <<~ERB
    <div class="bg-white rounded-lg border border-card-border shadow-sm <%= 'overflow-hidden' unless @padding %> <%= @html_attrs[:class] %>">
      <% if header? %>
        <div class="px-5 py-4 border-b border-card-border">
          <%= header %>
        </div>
      <% end %>

      <div class="<%= 'px-5 py-4' if @padding %>">
        <%= content %>
      </div>

      <% if footer? %>
        <div class="px-5 py-3 border-t border-card-border bg-hover/50">
          <%= footer %>
        </div>
      <% end %>
    </div>
  ERB
end
