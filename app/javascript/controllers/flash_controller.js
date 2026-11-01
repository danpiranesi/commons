import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.timeout = setTimeout(() => {
      this.element.style.transition = "opacity 300ms"
      this.element.style.opacity = "0"
      setTimeout(() => this.element.remove(), 300)
    }, 5000)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
