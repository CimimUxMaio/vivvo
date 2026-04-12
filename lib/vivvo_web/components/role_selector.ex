defmodule VivvoWeb.Components.RoleSelector do
  @moduledoc """
  LiveComponent for switching between user roles.

  Renders a styled button group with sliding animation that allows authenticated users
  to switch between their preferred roles. Only visible when the user has multiple
  preferred roles.
  """

  use VivvoWeb, :live_component

  alias Vivvo.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.sliding_selector
        value={to_string(@user.current_role)}
        on_select="switch_role"
        phx-target={@myself}
        class="bg-base-200 rounded-lg"
      >
        <:option :for={role <- @user.preferred_roles} value={to_string(role)}>
          <.role_icon role={role} />
          <span>{format_role_name(role)}</span>
        </:option>
      </.sliding_selector>
    </div>
    """
  end

  @impl true
  def handle_event("switch_role", %{"selected" => role}, socket) do
    user = socket.assigns.user

    # Only update if the role is valid and different from current
    if role && to_string(user.current_role) != role do
      case Accounts.update_user_current_role(user, %{current_role: role}) do
        {:ok, updated_user} ->
          # Notify parent LiveView to navigate to home page after role change
          send(self(), {:role_changed, updated_user})

          {:noreply,
           socket
           |> assign(:user, updated_user)}

        {:error, _changeset} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  defp format_role_name(role) do
    role
    |> Atom.to_string()
    |> String.capitalize()
  end

  defp role_icon(assigns) do
    icon_name =
      case assigns.role do
        :owner -> "hero-building-office"
        :tenant -> "hero-user"
        :manager -> "hero-briefcase"
        _ -> "hero-user"
      end

    assigns = assign(assigns, :icon_name, icon_name)

    ~H"""
    <.icon name={@icon_name} class="w-4 h-4" />
    """
  end
end
