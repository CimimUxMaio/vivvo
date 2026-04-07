/**
 * Theme management module for handling light/dark/system theme preferences.
 * Manages localStorage, data-theme attribute, and favicon updates.
 */

const STORAGE_KEY = "phx:theme"
const SYSTEM_THEME_QUERY = "(prefers-color-scheme: dark)"

/**
 * Get the system theme preference
 * @returns {"light" | "dark"}
 */
const getSystemTheme = () =>
  window.matchMedia(SYSTEM_THEME_QUERY).matches ? "dark" : "light"

/**
 * Get the effective theme (resolves "system" to actual light/dark)
 * @param {"system" | "light" | "dark"} theme
 * @returns {"light" | "dark"}
 */
const getEffectiveTheme = (theme) =>
  theme === "system" ? getSystemTheme() : theme

/**
 * Get the stored theme preference from localStorage
 * @returns {"system" | "light" | "dark"}
 */
const getStoredTheme = () => localStorage.getItem(STORAGE_KEY) || "system"

/**
 * Update favicon based on effective theme
 * @param {"light" | "dark"} effectiveTheme
 */
const updateFavicon = (effectiveTheme) => {
  const faviconEl = document.getElementById("favicon")

  if (faviconEl) {
    faviconEl.href = 
      effectiveTheme === "dark" 
        ? faviconEl.dataset.darkHref 
        : faviconEl.dataset.lightHref
  }
}

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

  // Update favicon based on effective theme
  updateFavicon(getEffectiveTheme(theme))
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
