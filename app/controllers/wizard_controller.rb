class WizardController < ApplicationController
  COPENHAGEN = ActiveSupport::TimeZone["Europe/Copenhagen"]

  def times
    @type_id    = params.require(:type_id)
    @start_date = Date.parse(params.require(:start_date))
    @end_date   = Date.parse(params.require(:end_date))
    @resource_type = ResourceType.find(@type_id)

    unless bookable_wizard_date?(@start_date) && bookable_wizard_date?(@end_date)
      redirect_to root_path, alert: t("wizard.alerts.dates_outside_period")
    end
  rescue Date::Error, ActiveRecord::RecordNotFound
    redirect_to root_path
  end

  def results
    @type_id = params.require(:type_id)
    @resource_type = ResourceType.find(@type_id)

    @start_at, @end_at = build_datetimes

    if @end_at <= @start_at
      redirect_to root_path, alert: t("wizard.alerts.end_before_start")
      return
    end

    if !admin? && @start_at < Time.current - Booking::PAST_START_SLACK
      redirect_to root_path, alert: t("wizard.alerts.start_in_past")
      return
    end

    visible_type_ids = visible_resource_type_ids(@type_id, @resource_type)

    # Only what can actually be booked for this exact slot — the same tests the
    # booking itself will face, so a car offered here is never refused on the
    # next screen: free (allowing for pooled inventory), and not held for its
    # fast bruger.
    overlapping = Booking
      .where(status: %w[active awaiting_return])
      .where("start_at < ? AND end_at > ?", @end_at, @start_at)
      .group(:resource_id).count

    @available_resources = Resource
      .where(status: "active", resource_type_id: visible_type_ids)
      .includes(:resource_type, :resource_prices, :resource_stat, :regular_user)
      .joins(:resource_type)
      .order("resource_types.sort_order, resources.name")
      .select do |r|
        overlapping.fetch(r.id, 0) < (r.inventory_count || 1) &&
          (admin? || !r.held_for?(@start_at, @end_at, current_user))
      end

    @unavailable_resources = Resource
      .where(status: "unavailable", resource_type_id: visible_type_ids)
      .includes(:resource_type)
      .joins(:resource_type)
      .order("resource_types.sort_order, resources.name")
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path
  end

  private

  # Builds start_at/end_at in the app's time zone. Accepts either:
  #   (a) start_date + start_hour + start_min + end_date + end_hour + end_min  (from search form)
  #   (b) start_at + end_at as ISO8601 strings (from handoff links)
  def build_datetimes
    if params[:start_at].present?
      start_at = Time.zone.parse(params[:start_at])
      end_at   = Time.zone.parse(params[:end_at])
    else
      start_date = Date.parse(params.require(:start_date))
      end_date   = Date.parse(params.require(:end_date))
      start_hour = params[:start_hour].to_i
      start_min  = params[:start_min].to_i
      end_hour   = params[:end_hour].to_i
      end_min    = params[:end_min].to_i

      start_at = Time.zone.local(start_date.year, start_date.month, start_date.day,
                                 start_hour, start_min)
      end_at   = Time.zone.local(end_date.year, end_date.month, end_date.day,
                                 end_hour, end_min)
    end
    [start_at, end_at]
  end

  def bookable_wizard_date?(date)
    SiteSetting.instance.bookable_date?(date, admin: admin?)
  end

  # "Other" aggregates all types that are not Car, Bicycle, or Toll.
  def visible_resource_type_ids(type_id_param, resource_type)
    all_types = ResourceType.all.to_a
    if type_id_param == "other"
      all_types.reject { |rt| rt.name.in?(%w[Car Bicycle Toll]) }.map(&:id)
    else
      [resource_type.id]
    end
  end
end
