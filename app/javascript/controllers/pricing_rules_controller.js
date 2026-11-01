import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "template", "rule"]

  add() {
    const content = this.templateTarget.content.cloneNode(true)
    this.containerTarget.appendChild(content)
  }

  remove(event) {
    event.target.closest("[data-pricing-rules-target='rule']").remove()
  }
}
