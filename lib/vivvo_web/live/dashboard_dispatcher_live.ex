defmodule VivvoWeb.DashboardDispatcherLive do
  @moduledoc """
  Dispatches to the appropriate dashboard based on user's current role.

  Immediately redirects in mount/3 - render/1 is never called.
  """
  use VivvoWeb, :live_view

  alias Vivvo.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if Scope.tenant?(scope) do
      {:ok, push_navigate(socket, to: ~p"/tenant/dashboard")}
    else
      {:ok, push_navigate(socket, to: ~p"/owner/dashboard")}
    end
  end
end
