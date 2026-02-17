defmodule VivvoWeb.RoleHooks do
  @moduledoc """
  LiveView hooks for role-related functionality.

  This module provides on_mount hooks for handling role switching
  and other role-related features in LiveViews.
  """

  use VivvoWeb, :verified_routes

  @doc """
  Attaches a handler for role change messages.

  When the RoleSelector component sends a `{:role_changed, updated_user}`
  message, this hook updates the current_scope and navigates to the home page.

  ## Usage

  Add this hook to your live_session in the router:

      live_session :authenticated,
        on_mount: [
          {VivvoWeb.UserAuth, :require_authenticated},
          {VivvoWeb.RoleHooks, :handle_role_changes}
        ] do
        # ... routes
      end
  """
  def on_mount(:handle_role_changes, _params, _session, socket) do
    {:cont,
     Phoenix.LiveView.attach_hook(socket, :role_change_handler, :handle_info, fn
       {:role_changed, updated_user}, socket ->
         new_scope = %{socket.assigns.current_scope | user: updated_user}

         {:halt,
          socket
          |> Phoenix.Component.assign(:current_scope, new_scope)
          |> Phoenix.LiveView.push_navigate(to: ~p"/")}

       _other, socket ->
         {:cont, socket}
     end)}
  end
end
