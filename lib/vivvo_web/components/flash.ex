defmodule VivvoWeb.Components.Flash do
  @moduledoc """
  Auto-dismissing flash messages with hover pause functionality.

  Features:
  - Auto-dismiss after 5 seconds
  - Timer pauses on hover
  - Click to close manually
  - Smooth enter/exit animations
  - Accessible with ARIA attributes
  """
  use Phoenix.LiveComponent

  import VivvoWeb.CoreComponents, only: [icon: 1]

  @default_duration 5000

  @doc """
  Renders a flash message with auto-dismiss functionality.

  ## Examples

      <.live_module
        module={VivvoWeb.Components.Flash}
        id="flash-info"
        kind={:info}
        message={"Payment accepted successfully"}
        duration={5000}
      />
  """
  attr :id, :string, required: true
  attr :kind, :atom, required: true, values: [:info, :error]
  attr :message, :string, required: true
  attr :duration, :integer, default: @default_duration

  def render(assigns) do
    # Extract phx-disconnected and phx-connected from assigns if present
    assigns =
      assigns
      |> assign_new(:phx_disconnected, fn -> assigns[:"phx-disconnected"] end)
      |> assign_new(:phx_connected, fn -> assigns[:"phx-connected"] end)
      |> assign_new(:hidden, fn -> assigns[:hidden] end)

    ~H"""
    <div
      id={@id}
      phx-hook="Flash"
      data-duration={@duration}
      data-kind={@kind}
      role="alert"
      hidden={@hidden}
      phx-disconnected={@phx_disconnected}
      phx-connected={@phx_connected}
      class={[
        "flash-message relative flex items-center gap-3 px-4 py-3 pb-4 rounded-xl shadow-lg border cursor-pointer transition-all duration-300 overflow-hidden",
        "w-full min-w-[320px] max-w-[420px] sm:min-w-[380px] sm:max-w-[480px]",
        "translate-x-0 bg-base-100 hover:bg-base-100/50 backdrop-blur-sm",
        @kind == :info && "border-success/30 shadow-success/10",
        @kind == :error && "border-error/30 shadow-error/10"
      ]}
      phx-click="close"
      phx-target={@myself}
    >
      <div class={[
        "absolute top-0 left-0 w-full h-full",
        @kind == :info && "bg-success/10",
        @kind == :error && "bg-error/10"
      ]}>
      </div>

      <%!-- Icon Container --%>
      <div class={[
        "flex-shrink-0 w-10 h-10 rounded-xl flex items-center justify-center",
        @kind == :info && "bg-success/10",
        @kind == :error && "bg-error/10"
      ]}>
        <.icon
          :if={@kind == :info}
          name="hero-check-circle"
          class="w-6 h-6 text-success"
        />
        <.icon
          :if={@kind == :error}
          name="hero-exclamation-circle"
          class="w-6 h-6 text-error"
        />
      </div>

      <%!-- Message Content --%>
      <div class="flex-1 min-w-0 pr-2">
        <p class={[
          "text-sm font-medium",
          @kind == :info && "text-success",
          @kind == :error && "text-error"
        ]}>
          <%= case @kind do %>
            <% :info -> %>
              Success
            <% :error -> %>
              Error
          <% end %>
        </p>
        <p class="text-sm text-base-content/80 mt-0.5 leading-relaxed">
          {@message}
        </p>
      </div>

      <%!-- Progress Bar --%>
      <div class="absolute bottom-0 left-0 right-0 h-1 overflow-hidden rounded-b-xl">
        <div
          class={[
            "flash-progress h-full transition-transform ease-linear origin-left",
            @kind == :info && "bg-success",
            @kind == :error && "bg-error"
          ]}
          style={"animation-duration: #{@duration}ms;"}
        />
      </div>
    </div>
    """
  end

  def mount(socket) do
    {:ok, assign(socket, :visible, true)}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:duration, fn -> @default_duration end)

    {:ok, socket}
  end

  def handle_event("close", _params, socket) do
    {:noreply, push_event(socket, "flash:close", %{id: socket.assigns.id})}
  end
end
