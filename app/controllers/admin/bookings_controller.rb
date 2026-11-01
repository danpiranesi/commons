module Admin
  class BookingsController < BaseController
    before_action :set_booking

    def edit
    end

    def update
      return transfer if params[:transfer].present?

      result = apply_correction
      if result.success?
        redirect_to edit_admin_booking_path(@booking), notice: t("admin.bookings.notices.#{result.notice_key}")
      else
        @error = result.error
        render :edit, status: :unprocessable_entity
      end
    end

    # Take a completed trip off the bill (car failure, missing key): refunds
    # what was charged and drops it from the month. See ReservationWaiverService.
    def destroy
      month  = @booking.billing_month
      result = ReservationWaiverService.call(booking: @booking, waived_by: current_user, reason: params[:reason])
      if result.success?
        redirect_to admin_monthly_overview_path(billing_month: month), status: :see_other,
                    notice: t("admin.bookings.notices.waived", resource: @booking.resource.display_name,
                              name: @booking.user.name)
      else
        redirect_to admin_monthly_overview_path(billing_month: month), status: :see_other,
                    alert: t("admin.bookings.alerts.waive_failed")
      end
    end

    private

    # Move the billed trip to another member and/or onto (or off) a work group.
    def transfer
      user  = User.find_by(id: params[:target_user_id]) || @booking.user
      group = params[:billing_group_id].present? ? BillingGroup.find_by(id: params[:billing_group_id]) : nil
      result = ReservationTransferService.call(booking: @booking, user: user, billing_group: group,
                                               transferred_by: current_user)
      if result.success?
        redirect_to edit_admin_booking_path(@booking),
                    notice: t("admin.bookings.notices.transferred", payer: @booking.billed_to,
                              amount: helpers.number_to_currency(result.new_amount, unit: "", precision: 2))
      else
        @error = result.error
        render :edit, status: :unprocessable_entity
      end
    end

    def set_booking
      @booking = Booking.includes(:user, resource: :resource_type).find(params[:id])
      unless @booking.status == "returned"
        redirect_to admin_monthly_overview_path, alert: t("admin.bookings.alerts.not_returned") and return
      end
      if @booking.billing_month.present? && ClosedBillingMonth.closed?(@booking.billing_month)
        redirect_to admin_monthly_overview_path(billing_month: @booking.billing_month),
                    alert: t("admin.bookings.alerts.month_closed",
                              month: ClosedBillingMonth.label_for(@booking.billing_month)) and return
      end
    end

    # Decide which correction path to apply based on what changed.
    # Returns a result duck-type with .success? and .notice_key.
    def apply_correction
      mileage_changed = correction_params[:end_mileage].present? &&
                        correction_params[:end_mileage].to_i != @booking.end_mileage.to_i
      start_changed   = correction_params[:start_mileage].present? &&
                        correction_params[:start_mileage].to_i != @booking.start_mileage.to_i
      new_return      = parsed_completed_at
      time_changed    = new_return.present? && new_return != @booking.completed_at
      month_changed   = correction_params[:billing_month].present? &&
                        correction_params[:billing_month] != @booking.billing_month

      if mileage_changed || start_changed || time_changed
        # One service call, so a reading and a return time corrected together are
        # re-priced once and post a single offsetting entry.
        svc = ReservationCorrectionService.call(
          booking:        @booking,
          ending_reading: (correction_params[:end_mileage] if mileage_changed),
          starting_reading: (correction_params[:start_mileage] if start_changed),
          completed_at:   (new_return if time_changed),
          corrected_by:   current_user
        )
        notice = time_changed && !mileage_changed && !start_changed ? :return_time_corrected : :mileage_corrected
        CorrectionResult.new(svc.success?, svc.success? ? notice : nil, svc.error)
      elsif month_changed
        target = correction_params[:billing_month]
        # Moving a trip *into* a closed month would change a sheet that has
        # already been signed off. The guard on set_booking only covers the month
        # the trip is currently in.
        if ClosedBillingMonth.closed?(target)
          return CorrectionResult.new(false, nil, :target_month_closed)
        end

        @booking.update!(billing_month: target)
        CorrectionResult.new(true, :billing_month_updated, nil)
      else
        CorrectionResult.new(true, :no_change, nil)
      end
    end

    def correction_params
      params.require(:booking).permit(:start_mileage, :end_mileage, :billing_month, :completed_at)
    end

    # The datetime-local field is naive; read it in the app's zone, to the
    # minute, and compare at the same precision so re-submitting the shown time
    # does not register as a change.
    def parsed_completed_at
      raw = correction_params[:completed_at]
      return nil if raw.blank?
      Time.zone.parse(raw)&.change(sec: 0)
    rescue ArgumentError
      nil
    end

    CorrectionResult = Struct.new(:success, :notice_key, :error) do
      def success? = success
    end
  end
end
