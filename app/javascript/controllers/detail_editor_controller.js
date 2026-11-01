import { Controller } from "@hotwired/stimulus"

// Field picker for the resource-detail and booking-detail templates.
// Simpler than design-editor: single slot, no separator, no live text preview.
// Chips are real hidden inputs so the form posts a plain array.
export default class extends Controller {
  static values = { fields: Object }

  addField(event) {
    const select = event.currentTarget
    const key = select.value
    if (!key) return

    const chips = this.element.querySelector(".detail-chips")
    if (chips.querySelector(`[data-field="${key}"]`)) {
      select.value = ""
      return // already present
    }

    chips.insertAdjacentHTML("beforeend", this.chipHTML(key))
    select.value = ""
  }

  removeField(event) {
    event.currentTarget.closest(".chip").remove()
  }

  chipHTML(key) {
    const label = this.fieldsValue[key] || key
    return `<span class="chip inline-flex items-center gap-1.5 rounded-full bg-[#E8E6E0] pl-3 pr-1.5 py-1 text-xs" data-field="${key}">
      <input type="hidden" name="detail[fields][]" value="${key}">
      <span>${label}</span>
      <button type="button" data-action="detail-editor#removeField"
              class="flex h-4 w-4 items-center justify-center rounded-full text-[#888880] hover:bg-black/10 hover:text-primary leading-none">&times;</button>
    </span>`
  }
}
