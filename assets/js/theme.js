/**
 * Theme management module for handling light/dark/system theme preferences.
 * Manages localStorage and data-theme attribute.
 * Note: favicon adapts automatically via CSS prefers-color-scheme in favicon.svg
 */

const STORAGE_KEY = "phx:theme"
const SYSTEM_THEME_QUERY = "(prefers-color-scheme: dark)"

/**
 * Get the stored theme preference from localStorage
 * @returns {"system" | "light" | "dark"}
 */
const getStoredTheme = () => localStorage.getItem(STORAGE_KEY) || "system"

/**
 * Set the theme and update all related UI elements
 * @param {"system" | "light" | "dark"} theme
 */
const setTheme = (theme) => {
  // Update localStorage
  if (theme === "system") {
    localStorage.removeItem(STORAGE_KEY)
  } else {
    localStorage.setItem(STORAGE_KEY, theme)
  }

  // Apply theme to document (DaisyUI handles "system" correctly)
  document.documentElement.setAttribute("data-theme", theme)
}

/**
 * Initialize the theme system
 */
export const initTheme = () => {
  // Initial theme setup
  const initialTheme = getStoredTheme()
  setTheme(initialTheme)

  // Listen for theme toggle events
  window.addEventListener("phx:set-theme", (e) => {
    const target = e.target.closest('[data-phx-theme]')
    if (target) {
      setTheme(target.dataset.phxTheme)
    }
  })

  // Listen for theme changes from other tabs
  window.addEventListener("storage", (e) => {
    if (e.key === STORAGE_KEY) {
      setTheme(e.newValue || "system")
    }
  })

  // Listen for system theme changes
  window.matchMedia(SYSTEM_THEME_QUERY).addEventListener("change", () => {
    const currentTheme = getStoredTheme()
    if (currentTheme === "system") {
      setTheme("system")
    }
  })
}
