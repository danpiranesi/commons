import { Controller } from "@hotwired/stimulus"

// Start-of-trip check-in: the odometer field is pre-filled with the last recorded
// reading and shown read-only. "Confirm" submits it as-is; "Edit" unlocks the
// field so the driver can correct it.
export default class extends Controller {
  static targets = ["input", "editButton", "confirmHint", "editHint"]

  edit() {
    this.inputTarget.readOnly = false
    this.inputTarget.classList.remove("bg-hover", "cursor-default")
    this.inputTarget.focus()
    this.inputTarget.select()
    if (this.hasEditButtonTarget) this.editButtonTarget.classList.add("hidden")
    if (this.hasConfirmHintTarget) this.confirmHintTarget.classList.add("hidden")
    if (this.hasEditHintTarget) this.editHintTarget.classList.remove("hidden")
  }
}
