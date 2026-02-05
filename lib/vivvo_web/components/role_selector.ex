defmodule VivvoWeb.Components.RoleSelector do
  @moduledoc """
  LiveComponent for switching between user roles.

  Renders a dropdown select that allows authenticated users to switch
  between their preferred roles. Only visible when the user has multiple
  preferred roles.
  """

  use VivvoWeb, :live_component

  alias Vivvo.Accounts

  @impl true
  def render(assigns) do
    options = format_options(assigns.user.preferred_roles)
    assigns = assign(assigns, :options, options)

    ~H"""
    <form id={@id} phx-change="switch_role" phx-target={@myself}>
      <.input
        type="select"
        name="current_role"
        value={@user.current_role}
        options={@options}
        class="w-32 select-sm"
      />
    </form>
    """
  end

  defp format_options(roles) do
    Enum.map(roles, fn role ->
      label =
        role
        |> Atom.to_string()
        |> String.capitalize()

      {label, role}
    end)
  end

  @impl true
  def handle_event("switch_role", %{"current_role" => role}, socket) do
    user = socket.assigns.user

    case Accounts.update_user_current_role(user, %{current_role: role}) do
      {:ok, _updated_user} ->
        {:noreply,
         socket
         |> push_navigate(to: ~p"/")}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end
end
