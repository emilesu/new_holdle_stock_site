import { Controller } from "@hotwired/stimulus"
import QRCode from "qrcode"

// 支付二维码渲染控制器
// 在 Native 支付场景下，将 code_url 渲染为二维码
export default class extends Controller {
  static targets = ["canvas"]

  connect() {
    const url = this.element.dataset.qrcodeUrl
    if (url) {
      this.render(url)
    }
  }

  render(url) {
    QRCode.toCanvas(this.canvasTarget, url, {
      width: 240,
      margin: 2,
      color: {
        dark: "#1f1f1f",
        light: "#ffffff"
      }
    }, (error) => {
      if (error) {
        console.error("QR code generation failed:", error)
      }
    })
  }
}
