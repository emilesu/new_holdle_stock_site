import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "mask", "tabPublish", "tabList", "contentInput"]

  connect() {
    const draft = sessionStorage.getItem("message_draft")
    if (draft && this.hasContentInputTarget) {
      this.contentInputTarget.value = draft
    }
  }

  open() {
    this.modalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.modalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
    if (this.hasContentInputTarget) {
      sessionStorage.setItem("message_draft", this.contentInputTarget.value)
    }
  }

  closeByMask(e) {
    if (e.target === this.maskTarget) this.close()
  }

  switchTabPublish() {
    this.tabPublishTarget.classList.remove("hidden")
    this.tabListTarget.classList.add("hidden")
  }

  switchTabList() {
    this.tabListTarget.classList.remove("hidden")
    this.tabPublishTarget.classList.add("hidden")
    this._loadList()
  }

  _loadList(page) {
    const url = page ? `/message_boards/my?page=${page}` : "/message_boards/my"
    fetch(url, {
      headers: { "Accept": "text/vnd.turbo-stream.html" }
    }).then(r => r.text()).then(html => {
      if (html) Turbo.renderStreamMessage(html)
    })
  }

  loadPage(e) {
    const page = e.currentTarget.dataset.page
    if (page) this._loadList(page)
  }
}