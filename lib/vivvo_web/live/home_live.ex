defmodule VivvoWeb.HomeLive do
  use VivvoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Home
        </.header>
      </div>
    </Layouts.app>
    """
  end
end
