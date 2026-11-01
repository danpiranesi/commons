import { Controller } from "@hotwired/stimulus"

// Two-step actions: the first button opens a panel, and the action itself lives
// inside it. Used for cancelling/deleting a booking, so one stray tap on a phone
// never throws a trip away.
export default class extends Controller {
  static targets = ["panel"]

  toggle() {
    const opening = this.panelTarget.hidden
    this.panelTarget.hidden = !opening
    if (opening) {
      this.panelTarget.scrollIntoView({ behavior: "smooth", block: "nearest" })
      this.panelTarget.querySelector("input, button")?.focus({ preventScroll: true })
    }
  }
}
