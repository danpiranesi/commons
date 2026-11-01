import { Controller } from "@hotwired/stimulus"

// Resets an unattended display back to its idle view after a stretch of no
// interaction. Used by the public wall schedule and the kiosk. Any
// pointer/key/touch activity restarts the countdown.
export default class extends Controller {
  static values = {
    timeout: { type: Number, default: 300000 }, // 5 minutes
    url: String,
    logout: Boolean // kiosk: drop the session on idle, not just reset the view
  }

  connect() {
    this.reset = this.reset.bind(this)
    this.activityEvents = ["pointerdown", "pointermove", "keydown", "touchstart", "wheel"]
    this.activityEvents.forEach((e) => window.addEventListener(e, this.reset, { passive: true }))
    this.start()
  }

  disconnect() {
    this.activityEvents.forEach((e) => window.removeEventListener(e, this.reset))
    clearTimeout(this.timer)
  }

  start() {
    this.timer = setTimeout(() => this.expire(), this.timeoutValue)
  }

  reset() {
    clearTimeout(this.timer)
    this.start()
  }

  expire() {
    if (this.logoutValue) {
      this.logout()
      return
    }
    const target = this.urlValue || window.location.pathname
    // Already idle → just refresh to a clean state; otherwise return to idle.
    if (window.location.pathname + window.location.search === target) {
      window.location.reload()
    } else {
      window.location.href = target
    }
  }

  // Kiosk: submit a DELETE to /logout (server drops the local session and, in
  // kiosk mode, redirects the wall back to the idle schedule).
  logout() {
    const form = document.createElement("form")
    form.method = "post"
    form.action = "/logout"
    form.insertAdjacentHTML("beforeend", '<input type="hidden" name="_method" value="delete">')
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (token) {
      form.insertAdjacentHTML("beforeend", `<input type="hidden" name="authenticity_token" value="${token}">`)
    }
    document.body.appendChild(form)
    form.submit()
  }
}
