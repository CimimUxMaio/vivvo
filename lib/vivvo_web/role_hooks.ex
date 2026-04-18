defmodule VivvoWeb.RoleHooks do
  @moduledoc """
  LiveView hooks for role-related functionality.

  This module provides on_mount hooks for handling role switching
  and other role-related features in LiveViews.
  """

  use VivvoWeb, :verified_routes

  @doc """
  Verifies the user has the required role.

  ## Examples

      # Require owner role
      on_mount [{VivvoWeb.RoleHooks, {:require_role, :owner}}]

      # Require tenant role
      on_mount [{VivvoWeb.RoleHooks, {:require_role, :tenant}}]
  """
  def on_mount({:require_role, required_role}, _params, _session, socket) do
    current_role = socket.assigns.current_scope.user.current_role

    if current_role == required_role do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You don't have permission to access this page.")
        |> Phoenix.LiveView.push_navigate(to: ~p"/")

      {:halt, socket}
    end
  end

  # Handle role changes by attaching an info handler
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
