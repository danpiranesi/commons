class BadgeComponent < ViewComponent::Base
  VARIANTS = {
    default: "bg-hover text-primary",
    success: "bg-success/10 text-success",
    danger: "bg-danger/10 text-danger",
    warning: "bg-amber-50 text-amber-700",
    sage: "bg-sage/10 text-sage"
  }.freeze

  def initialize(variant: :default, **html_attrs)
    @variant = variant.to_sym
    @html_attrs = html_attrs
  end

  def call
    css = class_names(
      "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium",
      VARIANTS[@variant]
    )

    content_tag :span, content, class: css, **@html_attrs
  end
end
