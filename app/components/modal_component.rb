class ModalComponent < ViewComponent::Base
  renders_one :footer

  def initialize(title:, size: :md)
    @title = title
    @size = size
  end

  SIZE_CLASSES = {
    sm: "max-w-sm",
    md: "max-w-lg",
    lg: "max-w-2xl"
  }.freeze

  erb_template <<~ERB
    <div data-controller="modal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div class="fixed inset-0 bg-black/30" data-action="click->modal#close"></div>
      <div class="relative bg-white rounded-lg border border-card-border shadow-lg w-full <%= SIZE_CLASSES[@size] %>">
        <div class="flex items-center justify-between px-5 py-4 border-b border-card-border">
          <h2 class="text-lg font-medium"><%= @title %></h2>
          <button data-action="modal#close" class="text-muted hover:text-primary p-1">
            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
          </button>
        </div>

        <div class="px-5 py-4">
          <%= content %>
        </div>

        <% if footer? %>
          <div class="px-5 py-3 border-t border-card-border bg-hover/50 flex items-center justify-end gap-3">
            <%= footer %>
          </div>
        <% end %>
      </div>
    </div>
  ERB
end
