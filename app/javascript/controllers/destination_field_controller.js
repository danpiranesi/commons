import { Controller } from "@hotwired/stimulus"

// Destination field with a "prefer not to say" opt-out. Ticking the box clears
// and disables the text box, so it's obvious no destination is being given;
// unticking hands the field back and focuses it.
export default class extends Controller {
  static targets = ["input", "toggle"]

  connect() {
    this.apply()
  }

  toggle() {
    this.apply()
    if (!this.toggleTarget.checked) this.inputTarget.focus()
  }

  apply() {
    const hidden = this.toggleTarget.checked
    this.inputTarget.disabled = hidden
    this.inputTarget.required = !hidden
    this.inputTarget.classList.toggle("opacity-50", hidden)
    if (hidden) this.inputTarget.value = ""
  }
}
