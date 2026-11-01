import { Controller } from "@hotwired/stimulus"

// Shows one month of the mobile booking calendar at a time, paged with prev/next
// arrows. All months stay in the DOM (their day buttons remain selectable by the
// wizard-date-picker controller); only visibility changes.
export default class extends Controller {
  static targets = ["month", "label", "prev", "next"]

  connect() {
    this.index = 0
    this.show()
  }

  next() {
    if (this.index < this.monthTargets.length - 1) {
      this.index++
      this.show()
    }
  }

  prev() {
    if (this.index > 0) {
      this.index--
      this.show()
    }
  }

  show() {
    this.monthTargets.forEach((m, i) => m.classList.toggle("hidden", i !== this.index))
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = this.monthTargets[this.index].dataset.label
    }
    if (this.hasPrevTarget) this.prevTarget.disabled = this.index === 0
    if (this.hasNextTarget) this.nextTarget.disabled = this.index === this.monthTargets.length - 1
  }
}
