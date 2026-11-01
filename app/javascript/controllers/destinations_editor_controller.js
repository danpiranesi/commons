import { Controller } from "@hotwired/stimulus"

// Grouped destinations editor on the admin settings page. Groups and destinations
// can be added/removed; the whole state is serialized to a hidden JSON field on
// every change, so the server just parses one field.
export default class extends Controller {
  static targets = ["groups", "output", "groupTemplate", "destinationTemplate"]

  connect() {
    this.serialize()
  }

  addGroup() {
    this.groupsTarget.appendChild(this.groupTemplateTarget.content.cloneNode(true))
    this.serialize()
  }

  removeGroup(event) {
    event.target.closest('[data-destinations-editor-target~="group"]')?.remove()
    this.serialize()
  }

  addDestination(event) {
    const group = event.target.closest('[data-destinations-editor-target~="group"]')
    const cities = group?.querySelector('[data-destinations-editor-target~="cities"]')
    if (!cities) return
    cities.appendChild(this.destinationTemplateTarget.content.cloneNode(true))
    this.serialize()
  }

  removeDestination(event) {
    event.target.closest('[data-destinations-editor-target~="city"]')?.remove()
    this.serialize()
  }

  // ── Reordering ──────────────────────────────────────────────────────
  // The saved order is the order members see, so groups and entries can be
  // shuffled here. Up/down buttons rather than drag-and-drop: they work with a
  // keyboard, on a phone, and need no library.

  moveGroupUp(event)        { this._shift(event, "group", -1) }
  moveGroupDown(event)      { this._shift(event, "group", +1) }
  moveDestinationUp(event)  { this._shift(event, "city", -1) }
  moveDestinationDown(event){ this._shift(event, "city", +1) }

  _shift(event, target, direction) {
    const el = event.target.closest(`[data-destinations-editor-target~="${target}"]`)
    if (!el) return
    const sibling = direction < 0 ? el.previousElementSibling : el.nextElementSibling
    if (!sibling) return
    direction < 0 ? sibling.before(el) : sibling.after(el)
    this.serialize()
    // Keep focus on the button the user pressed, so repeated presses keep moving
    // the same item instead of landing on whatever is now under the cursor.
    event.target.closest("button")?.focus()
  }

  serialize() {
    const data = []
    this.groupsTarget.querySelectorAll('[data-destinations-editor-target~="group"]').forEach(group => {
      const name = group.querySelector('[data-destinations-editor-target~="groupName"]')?.value.trim()
      if (!name) return
      const cities = [...group.querySelectorAll('[data-destinations-editor-target~="city"] input')]
        .map(input => input.value.trim())
        .filter(Boolean)
      if (cities.length === 0) return
      data.push({ group: name, cities })
    })
    this.outputTarget.value = JSON.stringify(data)
  }
}
