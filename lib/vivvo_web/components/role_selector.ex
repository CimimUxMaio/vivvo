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
    assigns = assign(assigns, :role_count, length(assigns.user.preferred_roles))

    ~H"""
    <div id={@id} class="relative">
      <div class="relative flex items-center bg-base-200/50 rounded-lg p-1 gap-0.5">
        <%!-- Sliding background indicator --%>
        <div
          class={[
            "absolute h-[calc(100%-0.5rem)] bg-base-100 rounded-md shadow-sm transition-all duration-300 ease-out",
            "top-1"
          ]}
          style={slider_position_style(@user.current_role, @user.preferred_roles)}
        />

        <%= for role <- @user.preferred_roles do %>
          <button
            type="button"
            phx-click="switch_role"
            phx-value-role={role}
            phx-target={@myself}
            class={[
              "relative z-10 flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-md transition-colors duration-200",
              @user.current_role == role && "text-primary",
              @user.current_role != role && "text-base-content/60 hover:text-base-content"
            ]}
          >
            <.role_icon role={role} />
            <span>{format_role_name(role)}</span>
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("switch_role", %{"role" => role}, socket) do
    user = socket.assigns.user

    # Only update if the role is actually different
    if user.current_role != String.to_existing_atom(role) do
      case Accounts.update_user_current_role(user, %{current_role: role}) do
        {:ok, _updated_user} ->
          {:noreply,
           socket
           |> push_navigate(to: ~p"/")}

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

  defp slider_position_style(current_role, preferred_roles) do
    # Calculate the position of the active role
    role_index = Enum.find_index(preferred_roles, &(&1 == current_role)) || 0
    role_count = length(preferred_roles)

    # Each role takes equal width
    width_percentage = 100 / role_count
    left_position = role_index * width_percentage

    "width: calc(#{width_percentage}% - 0.125rem); left: calc(#{left_position}% + 0.25rem);"
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
