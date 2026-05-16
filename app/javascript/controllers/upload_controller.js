import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "summary", "submit"]

  connect() {
    this.emptyLabel = this.summaryTarget.textContent
    this.submitTarget.disabled = true
  }

  showFiles() {
    const files = Array.from(this.inputTarget.files)
    this.submitTarget.disabled = files.length === 0
    this.summaryTarget.textContent = files.length === 0
      ? this.emptyLabel
      : files.map((file) => file.name).join(", ")
  }
}
