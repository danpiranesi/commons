# Renders a resource's identity block — templated title + up to two subtitle rows
# — the same way in every context. Only the type sizing differs per context; the
# *content* (which fields, in which order) comes from ResourceCardTemplate, so
# admin / calendar / mobile stay consistent.
#
#   render(ResourceCardComponent.new(resource:, size: :grid, lines: 2, electric_indicator: true))
class ResourceCardComponent < ViewComponent::Base
  SIZES = {
    default: { title: "text-sm font-medium",           subtitle: "text-xs text-muted" },
    grid:    { title: "font-medium text-xs truncate",  subtitle: "text-[10px] text-muted leading-tight truncate" },
    compact: { title: "text-sm font-medium truncate",  subtitle: "text-xs text-muted truncate" }
  }.freeze

  # lines: how many subtitle rows to show (0 lets a context suppress them, e.g. the
  # calendar grid shows an operational status line instead when a car is unavailable).
  def initialize(resource:, size: :default, lines: 2, electric_indicator: false, on_dark: false)
    @resource  = resource
    @size      = SIZES.key?(size) ? size : :default
    @lines     = lines
    @electric  = electric_indicator
    @on_dark   = on_dark
    @template  = ResourceCardTemplate.new(resource)
  end

  def title_class    = SIZES[@size][:title]

  # On the green calendar column the baked-in muted grey is unreadable, so swap it
  # for a translucent light tone that reads on the sage background.
  def subtitle_class
    base = SIZES[@size][:subtitle]
    return base unless @on_dark
    base.gsub("text-muted", "text-header-text/75")
  end

  def title
    @template.title
  end

  def subtitles
    [@template.subtitle1, @template.subtitle2].compact.first(@lines)
  end

  def show_electric?
    @electric && @resource.electric?
  end
end
