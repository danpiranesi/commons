import { Controller } from "@hotwired/stimulus"

// Expand / collapse every <details> in a list at once (the per-member trip
// lists on the monthly billing overview).
export default class extends Controller {
  static targets = ["item"]

  expand() { this.itemTargets.forEach((d) => { d.open = true }) }

  collapse() { this.itemTargets.forEach((d) => { d.open = false }) }
}
