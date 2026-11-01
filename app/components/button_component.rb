class ButtonComponent < ViewComponent::Base
  VARIANTS = {
    primary: "bg-[#E8E6E0] text-primary hover:bg-[#DDDBD5]",
    secondary: "bg-white text-primary border border-card-border hover:bg-hover",
    danger: "bg-danger/10 text-danger border border-danger/20 hover:bg-danger/15",
    ghost: "text-primary hover:bg-hover",
    # Solid traffic-light buttons for the two moments at the car: green starts a
    # trip, red ends it, so they can be told apart at a glance.
    go: "bg-success text-white hover:bg-[#4E6942]",
    stop: "bg-danger text-white hover:bg-[#8A3A24]"
  }.freeze

  SIZES = {
    sm: "px-3 py-1.5 text-xs",
    md: "px-4 py-2 text-sm",
    lg: "px-5 py-2.5 text-sm"
  }.freeze

  def initialize(variant: :primary, size: :md, href: nil, method: nil, disabled: false, full_width: false, **html_attrs)
    @variant = variant.to_sym
    @size = size.to_sym
    @href = href
    @method = method
    @disabled = disabled
    @full_width = full_width
    @html_attrs = html_attrs
  end

  def call
    css = class_names(
      "inline-flex items-center justify-center gap-2 rounded-md font-medium transition-colors cursor-pointer",
      # Keyboard users need to see where they are; the ring only shows for
      # keyboard focus, so it never appears on a mouse click.
      "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sage focus-visible:ring-offset-2",
      VARIANTS[@variant],
      SIZES[@size],
      "w-full" => @full_width,
      "opacity-50 pointer-events-none" => @disabled
    )

    if @href
      # pointer-events-none only stops the mouse — a disabled link is still
      # reachable by keyboard, so take it out of the tab order and mark it.
      attrs = @disabled ? @html_attrs.merge("aria-disabled": "true", tabindex: -1) : @html_attrs
      link_to @href, class: css, **attrs do
        content
      end
    else
      content_tag :button, content, class: css, disabled: @disabled, **@html_attrs
    end
  end
end
