# A labelled form field.
#
# The control is rendered *inside* the <label>, which gives it an implicit
# label association: screen readers announce the label when the control is
# focused, and clicking the label text focuses the control. (The control is
# passed as a block, so we can't put a `for` on an id we don't know.)
#
# Hint and error text are linked with aria-describedby so they are announced
# too, rather than being visual-only.
class FormFieldComponent < ViewComponent::Base
  def initialize(label:, error: nil, hint: nil, required: false, tooltip: nil)
    @label = label
    @error = error
    @hint = hint
    @required = required
    @tooltip = tooltip
    @id = "ff-#{SecureRandom.hex(4)}"
  end

  def described_by
    ids = []
    ids << "#{@id}-error" if @error
    ids << "#{@id}-hint"  if @hint && !@error
    ids.join(" ").presence
  end

  erb_template <<~ERB
    <div class="mb-4">
      <label class="block text-sm font-medium mb-1.5">
        <span class="flex items-center mb-1.5">
          <span><%= @label %><% if @required %><span class="text-danger ml-0.5" aria-hidden="true">*</span><span class="sr-only">(<%= t("forms.required") %>)</span><% end %></span>
          <% if @tooltip %><%= render(InfoTooltipComponent.new(text: @tooltip)) %><% end %>
        </span>
        <span class="block font-normal" <%= "aria-describedby=\#{described_by}".html_safe if described_by %>>
          <%= content %>
        </span>
      </label>
      <% if @error %>
        <p id="<%= @id %>-error" class="text-xs text-danger mt-1" role="alert"><%= @error %></p>
      <% end %>
      <% if @hint && !@error %>
        <p id="<%= @id %>-hint" class="text-xs text-muted mt-1"><%= @hint %></p>
      <% end %>
    </div>
  ERB
end
