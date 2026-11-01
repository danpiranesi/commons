import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["pricePreview", "duration", "conflict", "submit"]
  static values = { resourceId: Number, previewUrl: String, conflicts: Array }

  connect() {
    this.debounceTimer = null
    // Remember whether submit was disabled server-side (e.g. beyond the horizon)
    // so the conflict check never re-enables a button that should stay disabled.
    this.baseSubmitDisabled = this.hasSubmitTarget ? this.submitTarget.disabled : false
    this.updateDuration()
    this.checkConflict()
  }

  updatePreview() {
    this.updateDuration()
    this.checkConflict()
    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => this.fetchPreview(), 150)
  }

  // Read the chosen [start, end) as Date objects from the custom pickers.
  _readRange() {
    const q = (n) => this.element.querySelector(`[name="${n}"]`)?.value
    const sd = q("booking_start[date]"), sh = q("booking_start[hour]"), sm = q("booking_start[min]")
    const ed = q("booking_end[date]"), eh = q("booking_end[hour]"), em = q("booking_end[min]")
    if (!sd || !ed) return null
    const start = new Date(`${sd}T${(sh || "0").padStart(2, "0")}:${(sm || "0").padStart(2, "0")}`)
    const end = new Date(`${ed}T${(eh || "0").padStart(2, "0")}:${(em || "0").padStart(2, "0")}`)
    return { start, end }
  }

  // Warn + block submit when the chosen time overlaps any existing reservation.
  checkConflict() {
    if (!this.hasConflictTarget) return
    const range = this._readRange()
    let overlap = false
    if (range && range.end > range.start) {
      overlap = this.conflictsValue.some(c => {
        const cs = new Date(c.start), ce = new Date(c.end)
        return range.start < ce && range.end > cs
      })
    }
    this.conflictTarget.classList.toggle("hidden", !overlap)
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = overlap || this.baseSubmitDisabled
    }
  }

  // Read a Date from a custom time picker ("booking_start" / "booking_end").
  readTime(prefix) {
    const date = this.element.querySelector(`[name="${prefix}[date]"]`)?.value
    const hour = this.element.querySelector(`[name="${prefix}[hour]"]`)?.value
    const min = this.element.querySelector(`[name="${prefix}[min]"]`)?.value
    if (!date) return null
    return new Date(`${date}T${(hour || "0").padStart(2, "0")}:${(min || "0").padStart(2, "0")}`)
  }

  writeTime(prefix, dt) {
    const pad = (n) => n.toString().padStart(2, "0")
    const dateField = this.element.querySelector(`[name="${prefix}[date]"]`)
    const hourField = this.element.querySelector(`[name="${prefix}[hour]"]`)
    const minField = this.element.querySelector(`[name="${prefix}[min]"]`)
    if (dateField) {
      dateField.value = `${dt.getFullYear()}-${pad(dt.getMonth() + 1)}-${pad(dt.getDate())}`
      // The date lives in a hidden input behind our own picker, so the picker has
      // to be told the value moved or its visible label goes stale.
      dateField.dispatchEvent(new Event("change", { bubbles: true }))
    }
    if (hourField) hourField.value = dt.getHours().toString()
    if (minField) minField.value = dt.getMinutes() < 30 ? "0" : "30"
  }

  // Quick-duration buttons: set end = start + N hours (data-hours on the button).
  setDuration(event) {
    event.preventDefault()
    const hours = parseFloat(event.currentTarget.dataset.hours)
    const start = this.readTime("booking_start")
    if (!start || isNaN(hours)) return
    this.writeTime("booking_end", new Date(start.getTime() + hours * 3600 * 1000))
    this.updateDuration()
    this.updatePreview()
  }

  // Live "you'll have the car for X" readout under the pickers.
  updateDuration() {
    if (!this.hasDurationTarget) return
    const start = this.readTime("booking_start")
    const end = this.readTime("booking_end")
    if (!start || !end || end <= start) {
      this.durationTarget.textContent = this.durationTarget.dataset.invalidText || ""
      return
    }
    const totalMinutes = Math.round((end - start) / 60000)
    const days = Math.floor(totalMinutes / 1440)
    const hours = Math.floor((totalMinutes % 1440) / 60)
    const minutes = totalMinutes % 60
    const parts = []
    if (days) parts.push(`${days} ${this.durationTarget.dataset.daysUnit || "d"}`)
    if (hours) parts.push(`${hours} ${this.durationTarget.dataset.hoursUnit || "t"}`)
    if (minutes) parts.push(`${minutes} min`)
    const label = this.durationTarget.dataset.labelText || ""
    this.durationTarget.textContent = `${label} ${parts.join(" ")}`.trim()
  }

  fetchPreview() {
    const startDate = this.element.querySelector('[name="booking_start[date]"]')?.value
    const startHour = this.element.querySelector('[name="booking_start[hour]"]')?.value
    const startMin = this.element.querySelector('[name="booking_start[min]"]')?.value
    const endDate = this.element.querySelector('[name="booking_end[date]"]')?.value
    const endHour = this.element.querySelector('[name="booking_end[hour]"]')?.value
    const endMin = this.element.querySelector('[name="booking_end[min]"]')?.value

    if (!startDate || !endDate) return

    const startAt = `${startDate}T${startHour.padStart(2, '0')}:${startMin.padStart(2, '0')}`
    const endAt = `${endDate}T${endHour.padStart(2, '0')}:${endMin.padStart(2, '0')}`

    let url = `${this.previewUrlValue}?start_at=${encodeURIComponent(startAt)}&end_at=${encodeURIComponent(endAt)}`

    // Admin booking-for-another-member: include the target user so pricing reflects their tier
    const targetUserId = this.element.querySelector('input[name="target_user_id"]')?.value
    if (targetUserId) url += `&target_user_id=${targetUserId}`

    // On behalf of a group: its rate replaces the member's own in the estimate
    const groupId = this.element.querySelector('select[name="booking[billing_group_id]"]')?.value
    if (groupId) url += `&billing_group_id=${groupId}`

    const checkboxes = this.element.querySelectorAll('input[name="accessory_ids[]"]:checked')
    checkboxes.forEach(cb => {
      url += `&accessory_ids[]=${cb.value}`
    })

    const tollInputs = this.element.querySelectorAll('input[name^="toll_quantities"]')
    tollInputs.forEach(input => {
      const match = input.name.match(/toll_quantities\[(\d+)\]/)
      if (match && input.value > 0) {
        url += `&toll_quantities[${match[1]}]=${input.value}`
      }
    })

    const recurringToggle = this.element.querySelector('input[name="recurring"]')
    if (recurringToggle && recurringToggle.checked) {
      url += '&recurring=1'
      const recurringDays = this.element.querySelectorAll('input[name="recurring_days[]"]:checked')
      recurringDays.forEach(cb => {
        url += `&recurring_days[]=${cb.value}`
      })
    }

    fetch(url, {
      headers: {
        "Accept": "text/html",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      }
    })
      .then(response => response.text())
      .then(html => {
        if (html.trim()) {
          this.pricePreviewTarget.innerHTML = html
        }
      })
  }
}
