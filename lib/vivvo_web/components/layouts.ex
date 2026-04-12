defmodule VivvoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use VivvoWeb, :html

  alias Vivvo.Accounts.Scope

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200/30 flex flex-col">
      <%!-- Navigation Header --%>
      <.navbar current_scope={@current_scope} />

      <%!-- Main Content Area --%>
      <main class="flex-1 w-full px-4 sm:px-6 lg:px-8 py-6 sm:py-8">
        <div class="mx-auto max-w-7xl">
          {render_slot(@inner_block)}
        </div>
      </main>

      <%!-- Flash Messages --%>
      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Renders the navigation navbar with Vivvo branding.
  """
  attr :current_scope, :map, default: nil

  def navbar(assigns) do
    ~H"""
    <header
      class="sticky top-0 z-40 bg-base-100 border-b border-base-200 shadow-sm transition-all duration-300 ease-in-out relative"
      id="main-header"
    >
      <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div class="flex h-16 items-center justify-between">
          <%!-- Logo and Brand --%>
          <div class="flex items-center gap-4">
            <.link href={~p"/"} class="flex items-center gap-2 group">
              <.app_logo class="h-14" />
            </.link>

            <%!-- Desktop Navigation --%>
            <nav class="hidden md:flex items-center gap-1 ml-6">
              <%= if @current_scope && Scope.owner?(@current_scope) do %>
                <.link
                  href={~p"/properties"}
                  class="px-3 py-2 text-sm font-medium text-base-content/70 hover:text-primary rounded-lg hover:bg-base-200 transition-colors"
                >
                  <span class="flex items-center gap-2">
                    <.icon name="hero-building-office" class="w-4 h-4" /> Properties
                  </span>
                </.link>
              <% end %>
            </nav>
          </div>

          <%!-- Right Side Actions --%>
          <div class="flex items-center gap-2 sm:gap-4">
            <%!-- Mobile Menu Button --%>
            <button
              type="button"
              class="md:hidden p-2 text-base-content/70 hover:text-base-content hover:bg-base-200 rounded-lg transition-colors"
              phx-click={
                JS.toggle_class("max-h-0", to: "#mobile-menu")
                |> JS.toggle_class("max-h-[500px]", to: "#mobile-menu")
              }
            >
              <.icon name="hero-bars-3" class="w-6 h-6" />
            </button>

            <%!-- User Menu (Desktop) --%>
            <div class="hidden md:flex items-center gap-3">
              <%= if @current_scope do %>
                <%= if length(@current_scope.user.preferred_roles) > 1 do %>
                  <.live_component
                    module={VivvoWeb.Components.RoleSelector}
                    id="role-selector"
                    user={@current_scope.user}
                  />
                <% end %>

                <div class="dropdown dropdown-end dropdown-hover">
                  <div
                    tabindex="0"
                    role="button"
                    class="flex items-center gap-2 px-3 py-2 text-sm font-medium text-base-content/70 hover:text-base-content rounded-lg hover:bg-base-200 transition-colors cursor-pointer"
                  >
                    <div class="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center">
                      <span class="text-sm font-bold text-primary">
                        {String.first(@current_scope.user.first_name || "U")}
                      </span>
                    </div>
                    <span class="hidden lg:block max-w-[120px] truncate">
                      {@current_scope.user.first_name}
                    </span>
                    <.icon name="hero-chevron-down" class="w-4 h-4" />
                  </div>

                  <%!-- Dropdown Menu --%>
                  <div
                    tabindex="-1"
                    class="dropdown-content bg-base-100 rounded-xl shadow-lg border border-base-200 z-1 w-56 p-2"
                  >
                    <%!-- User Info --%>
                    <div class="px-3 py-2 border-b border-base-200 mb-1">
                      <p class="font-medium text-sm">
                        {@current_scope.user.first_name} {@current_scope.user.last_name}
                      </p>
                      <p class="text-xs text-base-content/60 truncate">
                        {@current_scope.user.email}
                      </p>
                    </div>

                    <%!-- Theme Selector --%>
                    <div class="px-3 py-2">
                      <p class="text-xs font-medium text-base-content/60 mb-2 uppercase tracking-wider">
                        Theme
                      </p>
                      <.theme_toggle_compact />
                    </div>

                    <div class="border-t border-base-200 my-1"></div>

                    <%!-- Menu Items --%>
                    <.link
                      href={~p"/users/settings"}
                      class="flex items-center gap-2 px-3 py-2 text-sm text-base-content hover:bg-base-200 rounded-lg transition-colors cursor-pointer"
                    >
                      <.icon name="hero-cog-6-tooth" class="w-4 h-4" /> Settings
                    </.link>
                    <.link
                      href={~p"/users/log-out"}
                      method="delete"
                      class="flex items-center gap-2 px-3 py-2 text-sm text-error hover:bg-error/10 rounded-lg transition-colors cursor-pointer"
                    >
                      <.icon name="hero-arrow-right-on-rectangle" class="w-4 h-4" /> Log out
                    </.link>
                  </div>
                </div>
              <% else %>
                <.theme_toggle_compact />
                <.link
                  href={~p"/users/log-in"}
                  class="px-4 py-2 text-sm font-medium text-primary hover:bg-primary/10 rounded-lg transition-colors"
                >
                  Log in
                </.link>
                <.link
                  href={~p"/users/register"}
                  class="px-4 py-2 text-sm font-medium bg-primary text-primary-content hover:bg-primary/90 rounded-lg transition-colors"
                >
                  Get Started
                </.link>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <%!-- Mobile Menu --%>
      <div
        id="mobile-menu"
        class="md:hidden absolute top-full left-0 right-0 border-t border-base-200 bg-base-100 shadow-lg overflow-hidden transition-all duration-300 ease-in-out max-h-0"
      >
        <div class="px-4 py-3 space-y-2">
          <%= if @current_scope && Scope.owner?(@current_scope) do %>
            <.link
              href={~p"/properties"}
              class="flex items-center gap-3 px-3 py-2 text-base font-medium text-base-content hover:bg-base-200 rounded-lg transition-colors"
            >
              <.icon name="hero-building-office" class="w-5 h-5" /> Properties
            </.link>
          <% end %>

          <%= if @current_scope do %>
            <div class="border-t border-base-200 pt-2 mt-2">
              <%!-- User Info --%>
              <div class="px-3 py-2 mb-2">
                <p class="font-medium">
                  {@current_scope.user.first_name} {@current_scope.user.last_name}
                </p>
                <p class="text-sm text-base-content/60">{@current_scope.user.email}</p>
              </div>

              <%= if length(@current_scope.user.preferred_roles) > 1 do %>
                <div class="px-3 py-2">
                  <p class="text-xs font-medium text-base-content/60 mb-2 uppercase tracking-wider">
                    Role
                  </p>
                  <.live_component
                    module={VivvoWeb.Components.RoleSelector}
                    id="menu-role-selector"
                    user={@current_scope.user}
                  />
                </div>
              <% end %>

              <%!-- Mobile Theme Selector --%>
              <div class="px-3 py-2">
                <p class="text-xs font-medium text-base-content/60 mb-2 uppercase tracking-wider">
                  Theme
                </p>
                <.theme_toggle_compact />
              </div>

              <div class="border-t border-base-200 my-2"></div>

              <.link
                href={~p"/users/settings"}
                class="flex items-center gap-3 px-3 py-2 text-base font-medium text-base-content hover:bg-base-200 rounded-lg transition-colors"
              >
                <.icon name="hero-cog-6-tooth" class="w-5 h-5" /> Settings
              </.link>
              <.link
                href={~p"/users/log-out"}
                method="delete"
                class="flex items-center gap-3 px-3 py-2 text-base font-medium text-error hover:bg-error/10 rounded-lg transition-colors"
              >
                <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5" /> Log out
              </.link>
            </div>
          <% else %>
            <div class="border-t border-base-200 pt-2 mt-2 space-y-2">
              <%!-- Mobile Theme Selector --%>
              <div class="px-3 py-2">
                <p class="text-xs font-medium text-base-content/60 mb-2 uppercase tracking-wider">
                  Theme
                </p>
                <.theme_toggle_compact />
              </div>

              <div class="border-t border-base-200 my-2"></div>

              <.link
                href={~p"/users/log-in"}
                class="flex items-center gap-3 px-3 py-2 text-base font-medium text-base-content hover:bg-base-200 rounded-lg transition-colors"
              >
                <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5" /> Log in
              </.link>
              <.link
                href={~p"/users/register"}
                class="flex items-center gap-3 px-3 py-2 text-base font-medium bg-primary text-primary-content rounded-lg transition-colors"
              >
                <.icon name="hero-user-plus" class="w-5 h-5" /> Get Started
              </.link>
            </div>
          <% end %>
        </div>
      </div>
    </header>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="fixed top-20 right-4 z-50 flex flex-col gap-3 pointer-events-none"
    >
      <%!-- Flash messages container - pointer-events-auto allows interaction --%>
      <div class="flex flex-col gap-3 pointer-events-auto">
        <%!-- Info Flash --%>
        <%= if info_msg = Phoenix.Flash.get(@flash, :info) do %>
          <.live_component
            module={VivvoWeb.Components.Flash}
            id="flash-info"
            kind={:info}
            message={info_msg}
            duration={5000}
          />
        <% end %>

        <%!-- Error Flash --%>
        <%= if error_msg = Phoenix.Flash.get(@flash, :error) do %>
          <.live_component
            module={VivvoWeb.Components.Flash}
            id="flash-error"
            kind={:error}
            message={error_msg}
            duration={8000}
          />
        <% end %>
      </div>

      <%!-- Connection Error Messages --%>
      <div class="flex flex-col gap-3 pointer-events-auto">
        <.live_component
          module={VivvoWeb.Components.Flash}
          id="client-error"
          kind={:error}
          message={gettext("We can't find the internet. Attempting to reconnect...")}
          duration={8000}
          hidden
          phx-disconnected={JS.remove_attribute("hidden", to: "#client-error")}
          phx-connected={JS.set_attribute({"hidden", ""}, to: "#client-error")}
        />

        <.live_component
          module={VivvoWeb.Components.Flash}
          id="server-error"
          kind={:error}
          message={gettext("Something went wrong! Attempting to reconnect...")}
          duration={8000}
          hidden
          phx-disconnected={JS.remove_attribute("hidden", to: "#server-error")}
          phx-connected={JS.set_attribute({"hidden", ""}, to: "#server-error")}
        />
      </div>
    </div>
    """
  end

  @doc """
  Compact theme toggle for use in dropdown menus and navbars.

  Uses CSS arbitrary variants to react to the `data-theme` attribute on the
  `<html>` element, so the indicator and active styling are fully client-side
  driven without any server state.
  """
  def theme_toggle_compact(assigns) do
    ~H"""
    <div class="relative flex bg-base-200 rounded-lg p-1">
      <%!-- Sliding background indicator --%>
      <div class={[
        "absolute h-[calc(100%-0.5rem)] bg-base-100 rounded-box shadow-sm transition-all duration-300 ease-out top-1",
        "w-[calc(33.33%-0.5rem)]",
        "[[data-theme=system]_&]:left-[calc(0%+0.25rem)]",
        "[[data-theme=light]_&]:left-[calc(33.33%+0.25rem)]",
        "[[data-theme=dark]_&]:left-[calc(66.66%+0.25rem)]"
      ]} />

      <button
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        class={[
          "flex-1 relative z-10 flex items-center justify-center gap-2 px-4 py-1.5 text-sm font-medium rounded-box transition-colors duration-200 cursor-pointer",
          "[[data-theme=system]_&]:text-primary",
          "text-base-content/60 hover:text-base-content"
        ]}
        title="System theme"
      >
        <.icon name="hero-computer-desktop" class="w-3.5 h-3.5" />
      </button>

      <button
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        class={[
          "flex-1 relative z-10 flex items-center justify-center gap-2 px-4 py-1.5 text-sm font-medium rounded-box transition-colors duration-200 cursor-pointer",
          "[[data-theme=light]_&]:text-primary",
          "text-base-content/60 hover:text-base-content"
        ]}
        title="Light theme"
      >
        <.icon name="hero-sun" class="w-3.5 h-3.5" />
      </button>

      <button
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        class={[
          "flex-1 relative z-10 flex items-center justify-center gap-2 px-4 py-1.5 text-sm font-medium rounded-box transition-colors duration-200 cursor-pointer",
          "[[data-theme=dark]_&]:text-primary",
          "text-base-content/60 hover:text-base-content"
        ]}
        title="Dark theme"
      >
        <.icon name="hero-moon" class="w-3.5 h-3.5" />
      </button>
    </div>
    """
  end
end
