import { Controller } from "@hotwired/stimulus"

// A Monday-first date picker for the booking form. A native <input type="date">
// defers to the phone's dialog, which on Android starts the week on Sunday. The
// value is an ISO date in a hidden input.
//
// Values come from data attributes so the month and weekday names stay in the
// page's language rather than the browser's.
export default class extends Controller {
  static targets = ["hidden", "display", "popover", "grid", "monthLabel"]
  static values = {
    months: Array,
    days: Array,
    min: String,
    max: String,
    today: String
  }

  connect() {
    this.viewMonth = this._parse(this.hiddenTarget.value) || new Date()
    this.viewMonth = new Date(this.viewMonth.getFullYear(), this.viewMonth.getMonth(), 1)
    this._renderDisplay()
    this._onOutside = (e) => { if (!this.element.contains(e.target)) this.close() }
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
    // Anything else that writes the date (quick-duration buttons, a restored
    // form) keeps the visible label in step.
    this._onExternal = () => this._renderDisplay()
    this.hiddenTarget.addEventListener("change", this._onExternal)
  }

  disconnect() {
    this.close()
    this.hiddenTarget.removeEventListener("change", this._onExternal)
  }

  toggle(event) {
    event.preventDefault()
    this._isOpen() ? this.close() : this.open()
  }

  _isOpen() {
    return !this.popoverTarget.classList.contains("hidden")
  }

  open() {
    this.popoverTarget.classList.remove("hidden")
    this.displayTarget.setAttribute("aria-expanded", "true")
    this._render()
    document.addEventListener("click", this._onOutside)
    document.addEventListener("keydown", this._onKey)
  }

  close() {
    if (!this._isOpen()) return
    this.popoverTarget.classList.add("hidden")
    this.displayTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this._onOutside)
    document.removeEventListener("keydown", this._onKey)
  }

  prevMonth(event) {
    event.preventDefault()
    this.viewMonth = new Date(this.viewMonth.getFullYear(), this.viewMonth.getMonth() - 1, 1)
    this._render()
  }

  nextMonth(event) {
    event.preventDefault()
    this.viewMonth = new Date(this.viewMonth.getFullYear(), this.viewMonth.getMonth() + 1, 1)
    this._render()
  }

  pick(event) {
    event.preventDefault()
    const iso = event.currentTarget.dataset.date
    if (!iso) return
    this.hiddenTarget.value = iso
    this._renderDisplay()
    this.close()
    // The price preview and conflict check listen for this on the hidden input.
    this.hiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  // ── rendering ───────────────────────────────────────────────────────────

  _render() {
    const year = this.viewMonth.getFullYear()
    const month = this.viewMonth.getMonth()
    this.monthLabelTarget.textContent = `${this.monthsValue[month]} ${year}`

    // Monday-first: getDay() is 0=Sun, so Sunday needs six leading blanks, not none.
    const first = new Date(year, month, 1)
    const lead = (first.getDay() + 6) % 7
    const daysInMonth = new Date(year, month + 1, 0).getDate()

    const cells = []
    for (const name of this.daysValue) {
      cells.push(`<div class="text-center text-[10px] text-muted font-medium py-1">${name}</div>`)
    }
    for (let i = 0; i < lead; i++) cells.push('<div></div>')

    for (let d = 1; d <= daysInMonth; d++) {
      const iso = this._iso(new Date(year, month, d))
      const disabled = (this.minValue && iso < this.minValue) || (this.maxValue && iso > this.maxValue)
      const selected = iso === this.hiddenTarget.value
      const isToday = iso === this.todayValue

      let cls = "w-full aspect-square flex items-center justify-center rounded-md text-xs "
      if (disabled) cls += "text-muted/40 cursor-not-allowed"
      else if (selected) cls += "bg-sage text-white font-semibold"
      else if (isToday) cls += "ring-1 ring-sage/50 hover:bg-sage/10"
      else cls += "hover:bg-sage/10"

      cells.push(
        `<button type="button" class="${cls}" data-date="${iso}"` +
        `${disabled ? " disabled" : ' data-action="click->date-picker#pick"'}` +
        `${selected ? ' aria-current="date"' : ""}>${d}</button>`
      )
    }
    this.gridTarget.innerHTML = cells.join("")
  }

  _renderDisplay() {
    const d = this._parse(this.hiddenTarget.value)
    this.displayTarget.textContent = d
      ? `${d.getDate()}. ${this.monthsValue[d.getMonth()]} ${d.getFullYear()}`
      : "—"
  }

  _parse(iso) {
    if (!iso) return null
    const [y, m, d] = iso.split("-").map(Number)
    if (!y || !m || !d) return null
    return new Date(y, m - 1, d)
  }

  _iso(date) {
    const pad = (n) => String(n).padStart(2, "0")
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
  }
}
