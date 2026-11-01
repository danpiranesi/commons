import { Controller } from "@hotwired/stimulus"

// Mobile booking wizard. Step 1 asks whether this is a multi-day trip, which
// decides whether an end DATE is needed:
//
//   Single-day:  pick_date → pick_start_time → pick_end_time → complete
//   Multi-day:   pick_start_date → pick_end_date → pick_start_time → pick_end_time → complete
//
// Times are chosen with two dropdowns (hour + minute) constrained to the bookable
// intervals (00:00–23:30, every 30 min; the return time must be after the start
// when it's the same day). The prompt above the calendar narrates each step;
// localized strings come in via the `strings` value so the JS stays language-agnostic.

export default class extends Controller {
  static targets = [
    "calendar", "prompt",
    "startGroup", "startSummary", "startTimeSlots",
    "endGroup", "endSummary", "endTimeSlots",
    "continueButton"
  ]
  static values = { periodStart: String, periodEnd: String, today: String, typeId: String, strings: Object }

  connect() {
    this.multiDay = false
    this._reset()
  }

  _reset() {
    this.startDate = null
    this.startTime = null
    this.endDate = null
    this.endTime = null
    this.phase = this.multiDay ? "pick_start_date" : "pick_date"
    this._refreshUI()
  }

  // ── Step 1: multi-day toggle ──────────────────────────────────────
  toggleMultiDay(event) {
    this.multiDay = event.currentTarget.checked
    this._reset()
  }

  // ── Day selection (calendar tap) ──────────────────────────────────
  selectDay(event) {
    const date = event.currentTarget.dataset.date
    if (!date) return

    if (!this.multiDay) {
      this.startDate = date
      this.endDate = date
      this.startTime = null
      this.endTime = null
      this.phase = "pick_start_time"
    } else if (this.phase === "pick_start_date") {
      this.startDate = date
      this.endDate = null
      this.startTime = null
      this.endTime = null
      this.phase = "pick_end_date"
    } else if (this.phase === "pick_end_date") {
      if (date < this.startDate) {
        this.startDate = date
        this.endDate = null
      } else {
        this.endDate = date
        this.phase = "pick_start_time"
      }
    } else {
      this.startDate = date
      this.endDate = null
      this.startTime = null
      this.endTime = null
      this.phase = "pick_end_date"
    }

    this._refreshUI()
  }

  // ── Time selection (hour + minute dropdowns) ──────────────────────
  timeChanged(event) {
    const container = event.currentTarget.closest("[data-time-container]")
    if (!container) return
    const role = container.dataset.timeContainer
    const hourSel = container.querySelector('[data-time-part="hour"]')
    const minSel = container.querySelector('[data-time-part="min"]')
    const minTime = role === "end" && this.endDate === this.startDate ? this.startTime : null
    const times = this._availableTimes(minTime)

    // Changing the hour re-populates the valid minutes for that hour.
    if (event.currentTarget === hourSel) {
      this._populateMinutes(minSel, hourSel.value, times)
    }

    const h = hourSel.value
    const m = minSel.value
    if (!h || !m) return

    if (role === "start") {
      this.startTime = `${h}:${m}`
      this.endTime = null
      this.phase = "pick_end_time"
    } else {
      this.endTime = `${h}:${m}`
      this.phase = "complete"
    }
    this._refreshUI()
  }

  // ── Revise a locked-in selection ──────────────────────────────────
  reviseStart() {
    this._reset()
  }

  reviseStartTime() {
    this.startTime = null
    this.endTime = null
    this.phase = "pick_start_time"
    this._refreshUI()
  }

  reviseEndTime() {
    this.endTime = null
    this.phase = "pick_end_time"
    this._refreshUI()
  }

  // ── Search — navigate to results ──────────────────────────────────
  search() {
    if (this.phase !== "complete") return

    const [startHour, startMin] = this.startTime.split(":").map(Number)
    const [endHour, endMin] = this.endTime.split(":").map(Number)

    const url = `/wizard/results?type_id=${encodeURIComponent(this.typeIdValue)}`
      + `&start_date=${this.startDate}&end_date=${this.endDate}`
      + `&start_hour=${startHour}&start_min=${startMin}`
      + `&end_hour=${endHour}&end_min=${endMin}`

    window.location.href = url
  }

  // ── Private: UI refresh ───────────────────────────────────────────
  _refreshUI() {
    this._refreshHighlights()
    this._refreshPrompt()
    this._refreshStartSummary()
    this._refreshStartTimeSlots()
    this._refreshEndSummary()
    this._refreshEndTimeSlots()
    this._refreshContinueButton()
  }

  _refreshPrompt() {
    const s = this.stringsValue
    let key = this.phase
    if (this.phase === "pick_end_time") key = this.multiDay ? "pick_end_time_multi" : "pick_end_time_single"
    this._setPrompt(s[key] || "")
  }

  // Swap the instruction with a slide: the current text slides out to the left,
  // the next one slides in from the right — signalling the step advanced without
  // moving the viewport.
  _setPrompt(text) {
    const el = this.promptTarget
    if (el.textContent.trim() === text) return

    el.style.transition = "transform 160ms ease-in, opacity 160ms ease-in"
    el.style.transform = "translateX(-40px)"
    el.style.opacity = "0"

    setTimeout(() => {
      el.textContent = text
      el.style.transition = "none"
      el.style.transform = "translateX(40px)"
      el.style.opacity = "0"
      void el.offsetWidth
      el.style.transition = "transform 220ms ease-out, opacity 220ms ease-out"
      el.style.transform = "translateX(0)"
      el.style.opacity = "1"
    }, 160)
  }

  _refreshStartSummary() {
    if (!this.hasStartSummaryTarget) return
    if (!this.startDate) {
      if (this.hasStartGroupTarget) this.startGroupTarget.classList.add("hidden")
      return
    }

    if (this.hasStartGroupTarget) this.startGroupTarget.classList.remove("hidden")
    const dateStr = this._fmtDay(this.startDate)
    const timeStr = this.startTime || ""
    const canRevise = !["pick_date", "pick_start_date"].includes(this.phase)
    this.startSummaryTarget.innerHTML = this._summaryPill(this.stringsValue.start, dateStr, timeStr, canRevise, "reviseStart")
  }

  _refreshStartTimeSlots() {
    if (!this.hasStartTimeSlotsTarget) return
    const el = this.startTimeSlotsTarget
    if (this.phase !== "pick_start_time") { el.classList.add("hidden"); return }

    const wasHidden = el.classList.contains("hidden")
    el.classList.remove("hidden")
    el.innerHTML = this._buildTimeDropdowns(this.startTime, "start", null)
    if (wasHidden && this.hasStartGroupTarget) this._flash(this.startGroupTarget)
  }

  _refreshEndSummary() {
    if (!this.hasEndSummaryTarget) return

    const show = this.endDate && (
      this.phase === "complete" ||
      this.phase === "pick_end_time" ||
      (this.multiDay && this.phase === "pick_start_time")
    )
    if (!show) {
      if (this.hasEndGroupTarget) this.endGroupTarget.classList.add("hidden")
      return
    }

    if (this.hasEndGroupTarget) this.endGroupTarget.classList.remove("hidden")
    const dateStr = this._fmtDay(this.endDate)
    const timeStr = this.endTime || ""
    const canRevise = this.phase === "complete"
    this.endSummaryTarget.innerHTML = this._summaryPill(this.stringsValue.end, dateStr, timeStr, canRevise, "reviseEndTime")
  }

  _refreshEndTimeSlots() {
    if (!this.hasEndTimeSlotsTarget) return
    const el = this.endTimeSlotsTarget
    if (this.phase !== "pick_end_time") { el.classList.add("hidden"); return }

    const wasHidden = el.classList.contains("hidden")
    el.classList.remove("hidden")
    const minTime = (this.endDate === this.startDate) ? this.startTime : null
    el.innerHTML = this._buildTimeDropdowns(this.endTime, "end", minTime)
    if (wasHidden && this.hasEndGroupTarget) this._flash(this.endGroupTarget)
  }

  _refreshContinueButton() {
    if (!this.hasContinueButtonTarget) return
    this.continueButtonTarget.classList.toggle("hidden", this.phase !== "complete")
  }

  _refreshHighlights() {
    this.calendarTarget.querySelectorAll("[data-date]").forEach(btn => {
      const d = btn.dataset.date
      const isStart = d === this.startDate
      const isEnd = this.endDate && d === this.endDate
      const inRange = this.startDate && this.endDate && d > this.startDate && d < this.endDate

      btn.classList.remove(
        "bg-[#6B7C60]", "text-white",
        "bg-[#E8E6E0]", "rounded-none", "rounded-r-none", "rounded-l-none"
      )

      if (isStart && isEnd) {
        btn.classList.add("bg-[#6B7C60]", "text-white")
      } else if (isStart) {
        btn.classList.add("bg-[#6B7C60]", "text-white", "rounded-r-none")
      } else if (isEnd) {
        btn.classList.add("bg-[#6B7C60]", "text-white", "rounded-l-none")
      } else if (inRange) {
        btn.classList.add("bg-[#E8E6E0]", "rounded-none")
      }
    })
  }

  // ── Private: helpers ──────────────────────────────────────────────

  // Intentionally a no-op: the wizard keeps the viewport stationary and signals
  // progress by animating the instruction instead of scrolling the page.
  _scrollTo(_el) {}

  // Pulse a sage ring around an element the moment it appears, so it's obvious a
  // selection is needed there. Re-triggerable (removes + reflows before adding).
  _flash(el) {
    el.classList.remove("flash-attention")
    void el.offsetWidth
    el.classList.add("flash-attention")
  }

  // Bookable time slots: the whole day, 00:00–23:30 every 30 min, after minTime.
  _availableTimes(minTime) {
    const pad = (n) => String(n).padStart(2, "0")
    const times = []
    for (let h = 0; h <= 23; h++) {
      for (const m of [0, 30]) {
        const t = `${pad(h)}:${pad(m)}`
        if (minTime && t <= minTime) continue
        times.push(t)
      }
    }
    return times
  }

  _buildTimeDropdowns(selectedTime, role, minTime = null) {
    const times = this._availableTimes(minTime)
    const hours = [...new Set(times.map(t => t.slice(0, 2)))]
    const selHour = selectedTime ? selectedTime.slice(0, 2) : ""
    const selMin = selectedTime ? selectedTime.slice(3, 5) : ""
    const minsForHour = selHour ? times.filter(t => t.slice(0, 2) === selHour).map(t => t.slice(3, 5)) : []

    const selCls = "rounded-md border border-card-border bg-white px-3 py-2.5 text-base font-medium text-primary focus:outline-none focus:ring-2 focus:ring-sage/30"

    const hourOpts = `<option value="" disabled ${selHour ? "" : "selected"}>${this.stringsValue.hour}</option>`
      + hours.map(h => `<option value="${h}" ${h === selHour ? "selected" : ""}>${h}</option>`).join("")
    const minOpts = `<option value="" disabled ${selMin ? "" : "selected"}>${this.stringsValue.minute}</option>`
      + minsForHour.map(m => `<option value="${m}" ${m === selMin ? "selected" : ""}>${m}</option>`).join("")

    return `<div class="flex items-center justify-center gap-2" data-time-container="${role}">
      <select data-time-part="hour" data-action="change->wizard-date-picker#timeChanged" class="${selCls}">${hourOpts}</select>
      <span class="text-lg font-semibold text-[#888880]">:</span>
      <select data-time-part="min" data-action="change->wizard-date-picker#timeChanged" class="${selCls}">${minOpts}</select>
    </div>`
  }

  _populateMinutes(minSel, hour, times) {
    const mins = hour ? times.filter(t => t.slice(0, 2) === hour).map(t => t.slice(3, 5)) : []
    const current = mins.includes(minSel.value) ? minSel.value : ""
    minSel.innerHTML = `<option value="" disabled ${current ? "" : "selected"}>${this.stringsValue.minute}</option>`
      + mins.map(m => `<option value="${m}" ${m === current ? "selected" : ""}>${m}</option>`).join("")
  }

  _summaryPill(label, dateStr, timeStr, canRevise, reviseAction) {
    const timeDisplay = timeStr ? ` · ${timeStr}` : ""
    const reviseBtn = canRevise
      ? `<button type="button" class="text-xs text-sage underline ml-2"
           data-action="click->wizard-date-picker#${reviseAction}">${this.stringsValue.change}</button>`
      : ""
    return `<div class="flex items-center justify-between">
      <div>
        <span class="text-xs text-[#888880]">${label}</span>
        <span class="ml-2 text-sm font-medium">${dateStr}${timeDisplay}</span>
      </div>
      ${reviseBtn}
    </div>`
  }

  _fmtDay(iso) {
    const [y, m, d] = iso.split("-").map(Number)
    const date = new Date(y, m - 1, d)
    return date.toLocaleDateString("da-DK", { weekday: "short", day: "numeric", month: "short" })
  }
}
