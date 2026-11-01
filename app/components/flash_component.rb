class FlashComponent < ViewComponent::Base
  TYPES = {
    notice: { bg: "bg-success/10", text: "text-success", border: "border-success/20" },
    alert: { bg: "bg-danger/10", text: "text-danger", border: "border-danger/20" }
  }.freeze

  def initialize(flash:)
    @flash = flash
  end

  erb_template <<~ERB
    <% @flash.each do |type, message| %>
      <% styles = TYPES[type.to_sym] || TYPES[:notice] %>
      <div class="<%= styles[:bg] %> <%= styles[:text] %> <%= styles[:border] %> border rounded-md px-4 py-3 text-sm mb-4" data-controller="flash" data-flash-target="message">
        <%= message %>
      </div>
    <% end %>
  ERB
end
