import { Controller } from "@hotwired/stimulus"

// Field-picker for the resource card template. Add/remove field chips per slot,
// tweak separators, and see a live preview built from a sample resource's values.
// Chips are real hidden inputs, so the form posts a normal nested params hash —
// this controller only manages the DOM and the preview.
export default class extends Controller {
  static values = { sample: Object, fields: Object }
  static targets = ["previewTitle", "previewSub1", "previewSub2"]

  static SLOTS = { title: "previewTitle", subtitle1: "previewSub1", subtitle2: "previewSub2" }

  connect() {
    this.render()
  }

  addField(event) {
    const select = event.currentTarget
    const key = select.value
    const slot = select.dataset.slot
    if (!key) return

    const chips = this.chipsFor(slot)
    chips.insertAdjacentHTML("beforeend", this.chipHTML(slot, key))
    select.value = ""
    this.render()
  }

  removeField(event) {
    event.currentTarget.closest(".chip").remove()
    this.render()
  }

  render() {
    for (const [slot, target] of Object.entries(this.constructor.SLOTS)) {
      const line = this.lineFor(slot)
      const el = this[`${target}Target`]
      el.textContent = line || (slot === "title" ? "—" : "")
    }
  }

  // ── helpers ───────────────────────────────────────────────

  chipsFor(slot) {
    return this.element.querySelector(`.chips[data-slot="${slot}"]`)
  }

  lineFor(slot) {
    const keys = Array.from(this.chipsFor(slot).querySelectorAll('input[type="hidden"]')).map((i) => i.value)
    let separator = this.separatorFor(slot)
    if (separator === "") separator = " "
    return keys
      .map((k) => (this.sampleValue[k] || "").trim())
      .filter((v) => v.length > 0)
      .join(separator)
  }

  separatorFor(slot) {
    const input = this.element.querySelector(`input[name="template[${slot}][separator]"]`)
    return input ? input.value : " "
  }

  chipHTML(slot, key) {
    const label = this.fieldsValue[key] || key
    return `<span class="chip inline-flex items-center gap-1.5 rounded-full bg-[#E8E6E0] pl-3 pr-1.5 py-1 text-xs" data-field="${key}">
      <input type="hidden" name="template[${slot}][fields][]" value="${key}">
      <span>${label}</span>
      <button type="button" data-action="design-editor#removeField" class="flex h-4 w-4 items-center justify-center rounded-full text-[#888880] hover:bg-black/10 hover:text-primary leading-none">&times;</button>
    </span>`
  }
}
