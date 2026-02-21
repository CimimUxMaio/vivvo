// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/vivvo"
import topbar from "../vendor/topbar"

/**
 * Flash message hook with auto-dismiss and hover pause functionality.
 * - Auto-dismisses after configured duration
 * - Pauses timer on mouse enter
 * - Resumes timer on mouse leave
 * - Closes immediately on click
 */
const Flash = {
  mounted() {
    this.duration = parseInt(this.el.dataset.duration, 10) || 5000
    this.remainingTime = this.duration
    this.startTime = null
    this.timerId = null
    this.isPaused = false
    this.isClosing = false

    // Get progress bar element
    this.progressBar = this.el.querySelector('.flash-progress')

    // Start the dismissal timer
    this.startTimer()

    // Add hover event listeners
    this.el.addEventListener('mouseenter', () => this.pauseTimer())
    this.el.addEventListener('mouseleave', () => this.resumeTimer())

    // Listen for close event from server
    this.handleFlashClose = (e) => {
      if (e.detail.id === this.el.id) {
        this.close()
      }
    }
    window.addEventListener('phx:flash:close', this.handleFlashClose)
  },

  destroyed() {
    this.clearTimer()
    window.removeEventListener('phx:flash:close', this.handleFlashClose)
  },

  startTimer() {
    if (this.isClosing) return

    this.startTime = Date.now()
    this.isPaused = false

    // Animate progress bar
    if (this.progressBar) {
      this.progressBar.style.animation = `flash-progress ${this.remainingTime}ms linear forwards`
    }

    this.timerId = setTimeout(() => {
      this.close()
    }, this.remainingTime)
  },

  pauseTimer() {
    if (this.isClosing || this.isPaused) return

    this.isPaused = true
    const elapsed = Date.now() - this.startTime
    this.remainingTime = Math.max(0, this.remainingTime - elapsed)

    this.clearTimer()

    // Pause progress bar animation
    if (this.progressBar) {
      this.progressBar.style.animationPlayState = 'paused'
    }
  },

  resumeTimer() {
    if (this.isClosing || !this.isPaused) return

    this.isPaused = false
    this.startTime = Date.now()

    // Resume progress bar animation
    if (this.progressBar) {
      this.progressBar.style.animationPlayState = 'running'
    }

    this.timerId = setTimeout(() => {
      this.close()
    }, this.remainingTime)
  },

  clearTimer() {
    if (this.timerId) {
      clearTimeout(this.timerId)
      this.timerId = null
    }
  },

  close() {
    if (this.isClosing) return
    this.isClosing = true

    this.clearTimer()

    // Add exit animation
    this.el.classList.add('flash-exit')

    // Wait for animation to complete before removing
    setTimeout(() => {
      // Push event to server to clear flash
      this.pushEventTo(this.el, 'lv:clear-flash', {key: this.el.dataset.kind})

      // Remove element from DOM
      this.el.remove()
    }, 300)
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Flash},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

