import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["typeSelect", "conditionalField"]
  static values = { typeNames: Object }

  connect() {
    this.toggle()
  }

  toggle() {
    const selectedId = this.typeSelectTarget.value
    const typeName = this.typeNamesValue[selectedId] || ""
    const hasType = selectedId !== ""

    this.conditionalFieldTargets.forEach(el => {
      const showFor = el.dataset.showFor
      let visible = false

      if (!hasType) {
        visible = false
      } else if (showFor === "all") {
        visible = true
      } else {
        const types = showFor.split(",").map(s => s.trim())
        visible = types.includes(typeName)
      }

      if (visible) {
        el.classList.remove("hidden")
        el.querySelectorAll("input, select, textarea").forEach(f => f.removeAttribute("disabled"))
      } else {
        el.classList.add("hidden")
        el.querySelectorAll("input, select, textarea").forEach(f => f.setAttribute("disabled", "disabled"))
      }
    })
  }
}
