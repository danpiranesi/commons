class BookingsController < ApplicationController
  def show
    @booking = Booking.find(params[:id])
    @resource = @booking.resource
    @price = @resource.price_for(@booking.user.user_type)
    @own_booking = @booking.user == current_user
    @booking_detail_template = BookingDetailTemplate.for(@resource.resource_type)
  end

  def new
    @resource = Resource.find(params[:resource_id])
    @target_user = resolve_target_user(params[:target_user_id])
    @booking_user = @target_user || current_user
    @price = @resource.price_for(@booking_user.user_type)

    if params[:start_at].present? && params[:end_at].present?
      prefill_start = Time.zone.parse(params[:start_at])
      prefill_end   = Time.zone.parse(params[:end_at])
      @date = prefill_start.to_date
    else
      @date = params[:date] ? Date.parse(params[:date]) : Date.current
    end

    @existing_bookings = Booking.where(resource: @resource, status: %w[active awaiting_return])
      .where("start_at < ? AND end_at > ?", @date.end_of_day, @date.beginning_of_day)
      .includes(:user)
      .order(:start_at)

    unless prefill_start
      prefill_start, prefill_end = find_available_gap(@existing_bookings, @date)
    end

    @booking = Booking.new(
      resource: @resource,
      user: @booking_user,
      start_at: prefill_start,
      end_at: prefill_end,
      actual_driver: @booking_user.name
    )

    @bookable = SiteSetting.instance.bookable_date?(@date, admin: admin?)
    @resource_conflicts = resource_conflict_ranges(@resource)
    @available_accessories = @resource.accessories.active.includes(:resource_type, :resource_prices)
    @all_users = User.order(:name) if admin?
  end

  def create
    parse_custom_times!
    @resource = Resource.find(booking_params[:resource_id])
    @target_user = resolve_target_user(params[:target_user_id])
    @booking_user = @target_user || current_user
    @price = @resource.price_for(@booking_user.user_type)

    if params[:recurring] == "1"
      create_recurring_bookings
    else
      create_single_booking
    end
  end

  def price_preview
    resource = Resource.find(params[:id])
    preview_user = resolve_target_user(params[:target_user_id]) || current_user
    price = resource.price_for(preview_user.user_type)

    start_at = Time.zone.parse(params[:start_at]) rescue nil
    end_at = Time.zone.parse(params[:end_at]) rescue nil

    if start_at && end_at && end_at > start_at && price
      hours = ((end_at - start_at) / 1.hour.to_f).round(1)
      time_cost = price.calculate_time_cost(hours)

      accessory_costs = calculate_accessory_costs(Array(params[:accessory_ids]), params[:toll_quantities], hours, current_user.user_type)

      # Split costs: tolls are one-time, accessories are per-day
      toll_costs = accessory_costs.select { |a| a[:toll] }
      non_toll_costs = accessory_costs.reject { |a| a[:toll] }
      toll_total = toll_costs.sum { |a| a[:cost] }
      non_toll_total = non_toll_costs.sum { |a| a[:cost] }

      # Recurring multiplier — days per week times the number of weeks repeated.
      recurring_days = Array(params[:recurring_days]).map(&:to_i).reject(&:zero?)
      recurring_weeks = params[:recurring_weeks].to_i.clamp(1, MAX_RECURRING_WEEKS)
      recurring_count = params[:recurring] == "1" && recurring_days.any? ? recurring_days.size * recurring_weeks : 0

      per_day_total = time_cost + non_toll_total
      total = recurring_count > 0 ? (per_day_total * recurring_count) + toll_total : per_day_total + toll_total

      # The rate the member is booking for/with. For a per-km (state) rate the km
      # aren't known yet, so the time part drops out and only the km rate is shown.
      category = preview_billing_category(preview_user)
      km_rate_display = category&.per_km? ? category.rate_value : price.km_rate
      if category&.multiplier? && category.rate_value.to_f != 1.0
        total = (total * category.rate_value).round(2)
        subtotal_out = (per_day_total * category.rate_value).round(2)
      elsif category&.per_km?
        total = 0                      # nothing charged for time; km on return
        subtotal_out = 0
      else
        subtotal_out = per_day_total
      end

      render partial: "bookings/price_preview", locals: {
        hours: hours,
        price: price,
        time_cost: time_cost,
        km_rate: km_rate_display,
        tracks_mileage: resource.tracks_mileage?,
        subtotal: subtotal_out,
        total: total,
        accessory_costs: accessory_costs,
        recurring_count: recurring_count,
        billing_rate_label: billing_rate_label(category),
        car_minimum: helpers.car_minimum_for(resource, category)
      }
    else
      render plain: "", status: :ok
    end
  end

  def edit
    @booking = Booking.find(params[:id])
    authorize_booking_edit!
    @resource = @booking.resource
    @price = @resource.price_for(@booking.user.user_type)
    @date = @booking.start_at.to_date
    @existing_bookings = Booking.where(resource: @resource, status: %w[active awaiting_return])
      .where("start_at < ? AND end_at > ?", @date.end_of_day, @date.beginning_of_day)
      .where.not(id: @booking.id)
      .includes(:user)
      .order(:start_at)
    @available_accessories = @resource.accessories.active.includes(:resource_type, :resource_prices)
  end

  def update
    @booking = Booking.find(params[:id])
    authorize_booking_edit!
    @resource = @booking.resource
    @price = @resource.price_for(@booking.user.user_type)
    parse_custom_times!
    previous_end = @booking.end_at
    # An admin may hand the booking to somebody else (e.g. a workshop run booked
    # by one admin and driven by another member).
    new_owner = resolve_target_user(params[:target_user_id])
    if new_owner && new_owner != @booking.user
      # The driver defaults to whoever booked; follow the new owner unless it
      # was set to somebody else on purpose.
      @booking.actual_driver = new_owner.name if @booking.actual_driver.blank? || @booking.actual_driver == @booking.user.name
      @booking.user = new_owner
    end

    @booking.creating_admin = admin?
    @booking.from_booking_form = true
    if @booking.with_resource_lock { @booking.update(booking_update_params) }
      @booking.apply_edit_penalty!(previous_end: previous_end)
      save_accessories(@booking)
      redirect_to booking_path(@booking), notice: t("bookings.notices.updated")
    else
      @date = @booking.start_at.to_date
      @existing_bookings = Booking.where(resource: @resource, status: %w[active awaiting_return])
        .where("start_at < ? AND end_at > ?", @date.end_of_day, @date.beginning_of_day)
        .where.not(id: @booking.id)
        .includes(:user).order(:start_at)
      @available_accessories = @resource.accessories.active.includes(:resource_type, :resource_prices)
      render :edit, status: :unprocessable_entity
    end
  end

  # Admin force-end for a booking that wasn't returned properly (nobody scanned
  # it back in). Routes through the same completion service as the QR/kiosk path,
  # so pricing, odometer math and the receipt stay identical — the only
  # difference is the admin enters the ending mileage from the detail view.
  def complete
    @booking = Booking.find(params[:id])
    unless admin?
      redirect_to booking_path(@booking), alert: t("errors.not_authorized") and return
    end

    result = ReservationCompletionService.call(
      booking:          @booking,
      ending_reading:   params[:ending_reading],
      completed_by:     current_user,
      allow_high_delta: params[:allow_high_delta] == "1"
    )

    if result.success?
      notice = result.amount.to_f.zero? ? t("bookings.notices.completed_free") :
                 t("bookings.notices.completed", amount: helpers.number_with_delimiter(result.amount))
      redirect_to booking_path(@booking), notice: notice
    else
      redirect_to booking_path(@booking), alert: completion_error_message(result)
    end
  end

  # Admin: move an open booking's end time, from the booking page, without the
  # full edit form. This is a correction, not the member releasing a slot, so
  # no shorten penalty applies and any billing floor is cleared.
  def adjust_end
    @booking = Booking.find(params[:id])
    unless admin? && @booking.open?
      redirect_to booking_path(@booking), alert: t("errors.not_authorized") and return
    end

    e = params[:booking_end] || {}
    new_end = Time.zone.parse("#{e[:date]} #{e[:hour]}:#{e[:min]}") rescue nil
    if new_end.nil?
      redirect_to booking_path(@booking), alert: t("bookings.alerts.invalid_times") and return
    end

    @booking.billed_until = nil
    if @booking.with_resource_lock { @booking.update(end_at: new_end) }
      redirect_to booking_path(@booking), notice: t("bookings.notices.end_adjusted", time: new_end.strftime("%-d/%-m %H:%M"))
    else
      redirect_to booking_path(@booking), alert: @booking.errors.full_messages.to_sentence
    end
  end

  # Remove a booking that should never have existed — a duplicate, or one entered
  # against the wrong car. Admins only, and only while nothing has been billed
  # for it; anything already on the accounts is cancelled or corrected instead.
  def destroy
    @booking = Booking.find(params[:id])

    unless @booking.deletable_by?(current_user)
      redirect_to booking_path(@booking), alert: t("bookings.alerts.cannot_delete")
      return
    end

    date = @booking.start_at.to_date
    @booking.destroy!
    redirect_to root_path(date: date), notice: t("bookings.notices.deleted"), status: :see_other
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey
    # deletable_by? clears this booking's own charge, but an accessory booked
    # alongside it may have been closed and billed separately. Anything with money
    # against it is cancelled or corrected, never erased.
    redirect_to booking_path(@booking), alert: t("bookings.alerts.cannot_delete")
  end

  def cancel
    @booking = Booking.find(params[:id])

    unless @booking.cancellable_by?(current_user)
      redirect_to booking_path(@booking), alert: t("bookings.alerts.cannot_cancel")
      return
    end

    @booking.cancel!(reason: params[:reason].presence || "Cancelled by #{current_user.name}")
    redirect_to root_path(date: @booking.start_at.to_date), notice: t("bookings.notices.cancelled", name: @booking.resource.display_name), allow_other_host: false, status: :see_other
  end

  private

  # Turn a completion-service failure into a flash message. Mirrors the mapping in
  # ReservationCompletionsController so the admin force-end reads the same.
  def completion_error_message(result)
    case result.error
    when :already_completed
      t("reservations.flash.already_completed")
    when :missing_reading, :missing_start_odometer
      t("reservations.flash.missing_reading")
    when :reading_too_low
      t("reservations.flash.reading_too_low", km: helpers.number_with_delimiter(result.meta[:current]))
    when :reading_implausible
      t("reservations.flash.reading_implausible", max: helpers.number_with_delimiter(result.meta[:max]))
    else
      t("reservations.flash.error")
    end
  end

  # The category driving the estimate: the chosen group's, else the member's own.
  def preview_billing_category(preview_user)
    group = BillingGroup.find_by(id: params[:billing_group_id]) if params[:billing_group_id].present?
    group&.billing_category || preview_user.billing_category
  end

  def billing_rate_label(category)
    return nil if category.nil? || (category.multiplier? && category.rate_value.to_f == 1.0)
    if category.per_km?
      t("bookings.price_preview.state_rate", rate: number_to_currency(category.rate_value, unit: "", precision: 2))
    else
      t("bookings.price_preview.rate_multiplier", factor: category.rate_value.to_f, name: category.name_da)
    end
  end

  def booking_params
    apply_private_destination(
      params.require(:booking).permit(:resource_id, :start_at, :end_at, :actual_driver, :payer, :notes, :destination, :rideshare_available, :may_return_early, :billing_group_id, :bridge_storebælt_qty, :bridge_øresund_qty)
    )
  end

  def booking_update_params
    apply_private_destination(
      params.require(:booking).permit(:start_at, :end_at, :actual_driver, :payer, :notes, :destination, :rideshare_available, :may_return_early, :billing_group_id, :bridge_storebælt_qty, :bridge_øresund_qty)
    )
  end

  # "Ikke din sag" is a checkbox beside the free-text destination; when it is
  # ticked the typed value is discarded and the private marker stored instead.
  def apply_private_destination(permitted)
    return permitted unless ActiveModel::Type::Boolean.new.cast(params[:destination_private])

    permitted.merge(destination: Booking::PRIVATE_DESTINATION)
  end

  def parse_custom_times!
    if params[:booking_start].present?
      s = params[:booking_start]
      params[:booking][:start_at] = Time.zone.parse("#{s[:date]} #{s[:hour]}:#{s[:min]}") rescue nil
    end
    if params[:booking_end].present?
      e = params[:booking_end]
      params[:booking][:end_at] = Time.zone.parse("#{e[:date]} #{e[:hour]}:#{e[:min]}") rescue nil
    end
  end

  def create_single_booking
    # The rolling horizon is enforced by Booking#within_booking_horizon;
    # booking_period is left blank.
    @booking = Booking.new(booking_params)
    @booking.user = @booking_user
    @booking.creating_admin = admin?
    @booking.from_booking_form = true
    @booking.start_mileage = @resource.resource_stat&.mileage if @resource.tracks_mileage?

    if @booking.with_resource_lock { @booking.save }
      save_accessories(@booking)
      redirect_to root_path(date: @booking.start_at.to_date), notice: t("bookings.notices.confirmed", name: @resource.display_name)
    else
      render_new_with_context
    end
  end

  # Re-render the booking form with everything it needs after a failed save, so
  # the member gets their input back rather than a bare error page.
  def render_new_with_context
    @date = @booking.start_at&.to_date || Date.current
    @bookable = SiteSetting.instance.bookable_date?(@date, admin: admin?)
    @existing_bookings = Booking.where(resource: @resource, status: %w[active awaiting_return])
      .where("start_at < ? AND end_at > ?", @date.end_of_day, @date.beginning_of_day)
      .includes(:user).order(:start_at)
    @resource_conflicts = resource_conflict_ranges(@resource)
    @available_accessories = @resource.accessories.active.includes(:resource_type, :resource_prices)
    @all_users = User.order(:name) if admin?
    render :new, status: :unprocessable_entity
  end

  # Repeat the same slot on chosen weekdays, over several weeks: commuters book
  # the coming work week ahead of time.
  MAX_RECURRING_WEEKS = 8

  # What every booking in a repeat shares. Compacted so a checkbox the form did
  # not send falls back to the column default rather than writing NULL.
  def recurring_attributes
    {
      resource: @resource,
      user: @booking_user,
      status: "active",
      destination: booking_params[:destination],
      rideshare_available: booking_params[:rideshare_available],
      billing_group_id: booking_params[:billing_group_id],
      may_return_early: booking_params[:may_return_early],
      actual_driver: booking_params[:actual_driver],
      payer: booking_params[:payer],
      notes: booking_params[:notes],
      start_mileage: @resource.resource_stat&.mileage
    }.compact
  end

  def create_recurring_bookings
    recurring_days = Array(params[:recurring_days]).map(&:to_i).select { |d| (1..7).cover?(d) }
    weeks = params[:recurring_weeks].to_i.clamp(1, MAX_RECURRING_WEEKS)

    start_at = booking_params[:start_at]
    end_at   = booking_params[:end_at]
    return redirect_to root_path, alert: t("bookings.alerts.invalid_times") unless start_at && end_at

    start_date = start_at.to_date
    # How many days the slot spans, so an overnight trip keeps its shape on every
    # repeat instead of ending before it starts (and being silently skipped).
    span_days = (end_at.to_date - start_date).to_i

    first_day = [start_date.beginning_of_week(:monday), Date.current].max
    last_day  = start_date.beginning_of_week(:monday) + (weeks * 7) - 1

    created = 0
    skipped = 0
    current_date = first_day

    while current_date <= last_day
      if recurring_days.include?(current_date.cwday)
        # in_time_zone, not to_time: the latter uses the server's zone.
        day_start = current_date.in_time_zone.change(hour: start_at.hour, min: start_at.min)
        day_end   = (current_date + span_days).in_time_zone.change(hour: end_at.hour, min: end_at.min)

        booking = Booking.new(recurring_attributes.merge(
          start_at: day_start,
          end_at: day_end
        ))
        booking.creating_admin = admin?
        booking.from_booking_form = true

        if booking.with_resource_lock { booking.save }
          if created == 0
            # First booking carries the one-time charges: tolls and bridges.
            booking.update(bridge_storebælt_qty: booking_params[:bridge_storebælt_qty].to_i,
                           bridge_øresund_qty: booking_params[:bridge_øresund_qty].to_i)
            save_accessories(booking)
          else
            save_accessories_without_tolls(booking)
          end
          created += 1
        else
          skipped += 1
        end
      end
      current_date += 1.day
    end

    if created.zero?
      @booking = Booking.new(booking_params)
      @booking.user = @booking_user
      @booking.errors.add(:base, t("bookings.alerts.recurring_none_created"))
      return render_new_with_context
    end

    msg = t("bookings.notices.recurring_created", count: created, name: @resource.display_name)
    msg += " #{t("bookings.notices.recurring_skipped", count: skipped)}" if skipped > 0
    redirect_to root_path(date: start_date), notice: msg
  end

  def save_accessories(booking)
    accessory_ids = Array(params[:accessory_ids]).map(&:to_i).reject(&:zero?)
    raw_tq = params[:toll_quantities] || {}
    toll_quantities = (raw_tq.respond_to?(:to_unsafe_h) ? raw_tq.to_unsafe_h : raw_tq).transform_values(&:to_i)

    booking.accessory_bookings.destroy_all
    booking.booking_accessories.destroy_all

    accessory_ids.each do |aid|
      booking.booking_accessories.create!(accessory_id: aid, quantity: 1)

      # Create a shadow booking on the accessory resource
      booking.accessory_bookings.create!(
        user: booking.user,
        resource_id: aid,
        booking_period: booking.booking_period,
        start_at: booking.start_at,
        end_at: booking.end_at,
        status: "active",
        notes: "Accessory for #{booking.resource.name} booking ##{booking.id}"
      )
    end

    # Tolls (quantity-based, no shadow booking needed)
    toll_quantities.each do |toll_id, qty|
      next if qty <= 0
      booking.booking_accessories.create!(accessory_id: toll_id.to_i, quantity: qty)
    end
  end

  def save_accessories_without_tolls(booking)
    accessory_ids = Array(params[:accessory_ids]).map(&:to_i).reject(&:zero?)

    booking.accessory_bookings.destroy_all
    booking.booking_accessories.destroy_all

    accessory_ids.each do |aid|
      booking.booking_accessories.create!(accessory_id: aid, quantity: 1)
      booking.accessory_bookings.create!(
        user: booking.user,
        resource_id: aid,
        booking_period: booking.booking_period,
        start_at: booking.start_at,
        end_at: booking.end_at,
        status: "active",
        notes: "Accessory for #{booking.resource.name} booking ##{booking.id}"
      )
    end
  end

  # Admins may book on behalf of any user by passing target_user_id.
  # Non-admins always book for themselves regardless of params.
  def resolve_target_user(id)
    return nil unless admin? && id.present?
    User.find_by(id: id)
  end

  # Members may edit a trip they have not started yet; admins may also edit one
  # that is already out.
  def authorize_booking_edit!
    unless @booking.user == current_user || admin?
      redirect_to root_path, alert: t("errors.not_authorized") and return
    end
    editable = @booking.active? || (admin? && @booking.status == "awaiting_return")
    unless editable
      redirect_to booking_path(@booking), alert: t("bookings.alerts.not_active") and return
    end
  end

  def calculate_accessory_costs(accessory_ids, toll_quantities, hours, user_type)
    costs = []

    ids = accessory_ids.map(&:to_i).reject(&:zero?)
    if ids.any?
      Resource.where(id: ids).includes(:resource_prices, :resource_type).each do |acc|
        acc_price = acc.price_for(user_type)
        cost = acc_price ? acc_price.calculate_time_cost(hours) : 0
        if acc_price && acc_price.hour_rate > 0
          label = "#{acc.name} (#{hours} hrs x #{acc_price.hour_rate.to_i} DKK)"
        elsif acc_price && acc_price.day_rate > 0
          days = (hours / 24.0).ceil
          days = 1 if days == 0
          label = "#{acc.name} (#{days} #{'day'.pluralize(days)} x #{acc_price.day_rate.to_i} DKK)"
        else
          label = acc.name
        end
        costs << { name: label, cost: cost, toll: false }
      end
    end

    # Tolls (price * quantity, one-time not per-day)
    raw_tq = toll_quantities || {}
    tq = (raw_tq.respond_to?(:to_unsafe_h) ? raw_tq.to_unsafe_h : raw_tq).transform_values(&:to_i)
    if tq.any?
      Resource.where(id: tq.keys.map(&:to_i)).includes(:resource_prices, :resource_type).each do |toll|
        qty = tq[toll.id.to_s]
        next if qty <= 0
        toll_price = toll.price_for(user_type)
        unit_price = toll_price&.hour_rate || 0
        costs << { name: "#{toll.name} (#{qty}x)", cost: qty * unit_price, toll: true }
      end
    end

    costs
  end

  # Round a time UP to the nearest 30-minute boundary.
  # 17:00 → 17:00, 17:01 → 17:30, 17:30 → 17:30, 17:31 → 18:00
  def next_half_hour_slot(time)
    remainder = time.min % 30
    if remainder == 0 && time.sec == 0
      time
    else
      (time + (30 - remainder).minutes).change(sec: 0)
    end
  end

  # Current/future reservations that would clash, for the live conflict check in
  # the form. Only for single-inventory resources — pooled ones (inventory > 1)
  # legitimately allow concurrent bookings, so the server handles those.
  def resource_conflict_ranges(resource)
    return [] if (resource.inventory_count || 1) > 1

    resource.bookings
            .where(status: %w[active awaiting_return])
            .where("end_at > ?", Time.current)
            .pluck(:start_at, :end_at)
            .map { |s, e| { start: s.iso8601, end: e.iso8601 } }
  end

  def find_available_gap(existing_bookings, date)
    default_start = if date == Date.current
      next_half_hour_slot(Time.current)
    else
      Time.zone.local(date.year, date.month, date.day, 8)
    end
    default_end = default_start + 2.hours
    return [default_start, default_end] if existing_bookings.empty?

    day_start = Time.zone.local(date.year, date.month, date.day, 6)
    day_end = Time.zone.local(date.year, date.month, date.day, 22)

    sorted = existing_bookings.sort_by(&:start_at)
    cursor = day_start

    sorted.each do |b|
      if cursor < b.start_at && (b.start_at - cursor) >= 1.hour
        return [cursor, b.start_at]
      end
      cursor = [cursor, b.end_at].max
    end

    return [cursor, day_end] if cursor < day_end && (day_end - cursor) >= 1.hour

    [default_start, default_end]
  end
end
