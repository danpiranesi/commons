# A small info icon that reveals a fuller explanation on hover or keyboard focus.
# Used next to a setting's label to keep the row clean while still offering detail.
#
#   <%= render(InfoTooltipComponent.new(text: "The long explanation…")) %>
class InfoTooltipComponent < ViewComponent::Base
  def initialize(text:)
    @text = text
  end

  erb_template <<~ERB
    <span class="group relative inline-flex items-center align-middle ml-1.5" tabindex="0" role="note" aria-label="<%= @text %>">
      <svg xmlns="http://www.w3.org/2000/svg" class="w-3.5 h-3.5 text-[#b6b6ae] group-hover:text-sage group-focus:text-sage transition-colors cursor-help" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>
      <span role="tooltip" class="pointer-events-none absolute left-1/2 top-full z-30 mt-2 hidden w-60 -translate-x-1/2 group-hover:block group-focus:block rounded-md bg-[#2C2C28] px-3 py-2 text-xs font-normal leading-snug text-white shadow-lg">
        <span class="absolute -top-1 left-1/2 -translate-x-1/2 w-2 h-2 rotate-45 bg-[#2C2C28]"></span>
        <%= @text %>
      </span>
    </span>
  ERB
end
