import { Controller } from "@hotwired/stimulus"

// Multi-select for batch QR-label printing on the admin resources list.
// Keeps the "Print labels (N)" button disabled until something is ticked, and
// lets each resource-type table's header checkbox toggle its own rows.
export default class extends Controller {
  static targets = ["checkbox", "submit", "count"]

  connect() {
    this.update()
  }

  update() {
    const n = this.selected().length
    if (this.hasCountTarget) this.countTarget.textContent = n
    if (this.hasSubmitTarget) this.submitTarget.disabled = n === 0
  }

  // Header checkbox toggles only the rows in its own table.
  toggleAll(event) {
    const table = event.currentTarget.closest("table")
    if (!table) return
    const checked = event.currentTarget.checked
    table
      .querySelectorAll('input[type="checkbox"][name="resource_ids[]"]')
      .forEach((box) => { box.checked = checked })
    this.update()
  }

  selected() {
    return this.checkboxTargets.filter((box) => box.checked)
  }
}
