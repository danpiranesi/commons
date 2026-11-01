import { Controller } from "@hotwired/stimulus"

// Server-side typeahead for picking a member when an admin books on their behalf.
// Debounces input → hits /admin/users/search?q= → renders a dropdown of matches.
// On select: fills the hidden target_user_id input, collapses the dropdown and
// fires booking-form#updatePreview so the price reflects the user's pricing tier.
export default class extends Controller {
  static values  = { searchUrl: String }
  static targets = ["input", "hidden", "results", "selected"]

  connect() {
    this.debounceTimer = null
    document.addEventListener("click", this.handleOutsideClick.bind(this))
  }

  disconnect() {
    document.removeEventListener("click", this.handleOutsideClick.bind(this))
  }

  search() {
    const q = this.inputTarget.value.trim()
    clearTimeout(this.debounceTimer)

    if (q.length < 2) {
      this.clearResults()
      return
    }

    this.debounceTimer = setTimeout(() => this.fetchResults(q), 200)
  }

  fetchResults(q) {
    fetch(`${this.searchUrlValue}?q=${encodeURIComponent(q)}`, {
      headers: { "Accept": "application/json",
                 "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content }
    })
      .then(r => r.json())
      .then(users => this.renderResults(users))
  }

  renderResults(users) {
    if (!users.length) {
      this.resultsTarget.innerHTML = `<div class="px-3 py-2 text-xs text-[#888880]">No members found</div>`
      this.resultsTarget.classList.remove("hidden")
      return
    }

    this.resultsTarget.innerHTML = users.map(u => `
      <button type="button"
              class="w-full text-left px-3 py-2 hover:bg-hover transition-colors"
              data-action="user-search#select"
              data-user-id="${u.id}"
              data-user-name="${u.name}"
              data-user-type="${u.user_type}">
        <div class="text-sm font-medium">${u.name}</div>
        <div class="text-xs text-[#888880]">${u.initials || ""} ${u.housing_unit ? "· " + u.housing_unit : ""} · ${u.user_type}</div>
      </button>
    `).join("")
    this.resultsTarget.classList.remove("hidden")
  }

  select(event) {
    const btn = event.currentTarget
    const id   = btn.dataset.userId
    const name = btn.dataset.userName

    this.hiddenTarget.value = id
    this.inputTarget.value  = name
    this.selectedTarget.textContent = name
    this.clearResults()

    // Re-price for the newly selected user
    const bookingForm = this.element.closest("[data-controller~='booking-form']")
    if (bookingForm) {
      bookingForm.dispatchEvent(new Event("booking-form:user-changed"))
      // Direct call if the booking-form controller is on the same element
      const bfController = this.application.getControllerForElementAndIdentifier(bookingForm, "booking-form")
      if (bfController) bfController.updatePreview()
    }
  }

  clearResults() {
    this.resultsTarget.innerHTML = ""
    this.resultsTarget.classList.add("hidden")
  }

  clear() {
    this.inputTarget.value = ""
    this.hiddenTarget.value = ""
    this.selectedTarget.textContent = ""
    this.clearResults()
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.clearResults()
    }
  }
}
