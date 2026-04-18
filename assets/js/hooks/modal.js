/**
 * Modal hook for native HTML dialog element with responsive behavior.
 *
 * Uses the native <dialog> element API:
 * - showModal() / close() for open/close state
 * - Native ESC key and backdrop close support
 * - Accessible focus management
 *
 * Responsibilities:
 * - Open/close via showModal() and close() when events dispatched
 * - Handle "modal:open" and "modal:close" custom events (from client or server)
 * - Push optional on_open event to LiveView when modal opens
 * - Push optional on_close event to LiveView when modal closes
 * - Re-open after LiveView DOM patches (updated() callback)
 * - Drag-to-dismiss on mobile
 */
const Modal = {
  mounted() {
    this.box = this.el.querySelector(".modal-box")
    this.onOpenEvent = this.el.dataset.onOpen
    this.onCloseEvent = this.el.dataset.onClose
    this.eventTarget = this.el.getAttribute("phx-target")
    this.isOpen = false
    this.isClosing = false
    this.isDragging = false
    this.startY = 0
    this.currentY = 0
    this.startTime = 0

    // Thresholds for closing via drag
    this.VELOCITY_THRESHOLD = 0.5 // px/ms
    this.DISTANCE_THRESHOLD = 0.25 // 25% of modal height

    // Bind methods
    this.handleOpenEvent = this.handleOpenEvent.bind(this)
    this.handleCloseEvent = this.handleCloseEvent.bind(this)
    this.handleDialogClose = this.handleDialogClose.bind(this)
    this.handleServerOpen = this.handleServerOpen.bind(this)
    this.handleServerClose = this.handleServerClose.bind(this)
    this.handleDragStart = this.handleDragStart.bind(this)
    this.handleDragMove = this.handleDragMove.bind(this)
    this.handleDragEnd = this.handleDragEnd.bind(this)
    this.handleResize = this.handleResize.bind(this)

    // Listen for custom events to open/close (client-side via JS.dispatch)
    this.el.addEventListener("modal:open", this.handleOpenEvent)
    this.el.addEventListener("modal:close", this.handleCloseEvent)

    // Listen for native dialog close event (ESC, form[method="dialog"], close())
    this.el.addEventListener("close", this.handleDialogClose)

    // Listen for server-pushed events via push_event/3
    this.handleEvent("modal:open", this.handleServerOpen)
    this.handleEvent("modal:close", this.handleServerClose)

    // Only enable drag on mobile (below sm breakpoint - 640px)
    this.dragEventsBound = false
    if (window.innerWidth < 640) {
      this.bindDragEvents()
      this.dragEventsBound = true
    }

    // Re-bind drag events on resize to handle mobile/desktop transitions
    window.addEventListener("resize", this.handleResize)
  },

  updated() {
    // Re-sync state if LiveView re-rendered while modal is open.
    // LiveView may strip the `open` attribute during DOM diffing.
    if (this.isOpen && !this.el.open) {
      // Save and restore focus: showModal() moves focus to the first
      // focusable element, which would steal focus from the active input.
      const activeElement = document.activeElement
      this.el.showModal()
      if (activeElement && this.el.contains(activeElement)) {
        activeElement.focus()
      }
    }
  },

  destroyed() {
    this.el.removeEventListener("modal:open", this.handleOpenEvent)
    this.el.removeEventListener("modal:close", this.handleCloseEvent)
    this.el.removeEventListener("close", this.handleDialogClose)

    this.unbindDragEvents()
    window.removeEventListener("resize", this.handleResize)
  },

  /**
   * Handle window resize to bind/unbind drag events based on breakpoint
   */
  handleResize() {
    const isMobile = window.innerWidth < 640

    if (isMobile && !this.dragEventsBound) {
      this.bindDragEvents()
      this.dragEventsBound = true
    } else if (!isMobile && this.dragEventsBound) {
      this.unbindDragEvents()
      this.dragEventsBound = false
    }
  },

  /**
   * Handle server-pushed "modal:open" event.
   * Called when server wants to open the modal programmatically.
   */
  handleServerOpen({id}) {
    // Only open if this is the target modal
    if (id && id === this.el.id && !this.el.open) {
      this.el.showModal()
      this.isOpen = true

      if (this.onOpenEvent) {
        this.pushModalEvent(this.onOpenEvent)
      }
    }
  },

  /**
   * Handle server-pushed "modal:close" event.
   * Called when server wants to close the modal programmatically.
   */
  handleServerClose({id}) {
    // Only close if this is the target modal
    if (id && id === this.el.id && this.el.open) {
      this.el.close()
    }
  },

  /**
   * Handle custom "modal:open" event - called by open_modal/1 JS command
   */
  handleOpenEvent() {
    if (this.el.open) return

    this.el.showModal()
    this.isOpen = true

    if (this.onOpenEvent) {
      this.pushModalEvent(this.onOpenEvent)
    }
  },

  /**
   * Handle custom "modal:close" event - called by close_modal/1 JS command
   */
  handleCloseEvent() {
    if (!this.el.open) return

    this.el.close()
  },

  /**
   * Handle native dialog "close" event - fires when modal closes via
   * ESC key, form[method="dialog"] submit, or close() call.
   */
  handleDialogClose() {
    this.isOpen = false

    if (this.onCloseEvent) {
      this.pushModalEvent(this.onCloseEvent)
    }
  },

  bindDragEvents() {
    const dragHandle = this.el.querySelector("[data-drag-handle]")
    if (!dragHandle) return

    // Touch events
    dragHandle.addEventListener("touchstart", this.handleDragStart, {
      passive: false,
    })
    document.addEventListener("touchmove", this.handleDragMove, {
      passive: false,
    })
    document.addEventListener("touchend", this.handleDragEnd)

    // Mouse events
    dragHandle.addEventListener("mousedown", this.handleDragStart)
    document.addEventListener("mousemove", this.handleDragMove)
    document.addEventListener("mouseup", this.handleDragEnd)
  },

  unbindDragEvents() {
    const dragHandle = this.el.querySelector("[data-drag-handle]")
    if (!dragHandle) return

    dragHandle.removeEventListener("touchstart", this.handleDragStart)
    document.removeEventListener("touchmove", this.handleDragMove)
    document.removeEventListener("touchend", this.handleDragEnd)
    dragHandle.removeEventListener("mousedown", this.handleDragStart)
    document.removeEventListener("mousemove", this.handleDragMove)
    document.removeEventListener("mouseup", this.handleDragEnd)
  },

  handleDragStart(e) {
    // Prevent default to stop scrolling while dragging
    e.preventDefault()

    this.isDragging = true
    this.startY = this.getClientY(e)
    this.currentY = 0
    this.startTime = Date.now()

    // Add dragging class to disable CSS transitions
    this.el.classList.add("modal-dragging")
  },

  handleDragMove(e) {
    if (!this.isDragging) return
    e.preventDefault()

    const deltaY = this.getClientY(e) - this.startY

    // Only allow dragging down (positive delta)
    if (deltaY > 0) {
      this.currentY = deltaY
      // Apply drag offset via CSS custom property
      if (this.box) {
        this.box.style.setProperty("--drag-y", `${deltaY}px`)
      }
    }
  },

  handleDragEnd() {
    if (!this.isDragging) return
    this.isDragging = false

    const modalHeight = this.box?.offsetHeight || window.innerHeight
    const dragDuration = Date.now() - this.startTime
    const velocity = this.currentY / dragDuration
    const thresholdDistance = modalHeight * this.DISTANCE_THRESHOLD

    // Determine if modal should close
    const shouldClose =
      this.currentY > thresholdDistance || velocity > this.VELOCITY_THRESHOLD

    // Remove dragging class to re-enable CSS transitions
    this.el.classList.remove("modal-dragging")

    // Clear the drag offset - CSS transition will animate it back or close will kick in
    if (this.box) {
      this.box.style.removeProperty("--drag-y")
    }

    if (shouldClose) {
      this.el.close()
    }
  },

  getClientY(e) {
    return e.touches ? e.touches[0].clientY : e.clientY
  },

  /**
   * Push an event to the server, targeting a specific element if eventTarget is set.
   */
  pushModalEvent(event) {
    if (this.eventTarget) {
      this.pushEventTo(this.eventTarget, event)
    } else {
      this.pushEvent(event)
    }
  },
}

export default Modal
