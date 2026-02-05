defmodule VivvoWeb.PropertyLive.Form do
  use VivvoWeb, :live_view

  alias Vivvo.Properties
  alias Vivvo.Properties.Property

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage property records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="property-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:address]} type="text" label="Address" />
        <.input field={@form[:area]} type="number" label="Area" />
        <.input field={@form[:rooms]} type="number" label="Rooms" />
        <.input field={@form[:notes]} type="textarea" label="Notes" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Property</.button>
          <.button navigate={return_path(@current_scope, @return_to, @property)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    property = Properties.get_property!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Property")
    |> assign(:property, property)
    |> assign(:form, to_form(Properties.change_property(socket.assigns.current_scope, property)))
  end

  defp apply_action(socket, :new, _params) do
    property = %Property{user_id: socket.assigns.current_scope.user.id}

    socket
    |> assign(:page_title, "New Property")
    |> assign(:property, property)
    |> assign(:form, to_form(Properties.change_property(socket.assigns.current_scope, property)))
  end

  @impl true
  def handle_event("validate", %{"property" => property_params}, socket) do
    changeset =
      Properties.change_property(
        socket.assigns.current_scope,
        socket.assigns.property,
        property_params
      )

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"property" => property_params}, socket) do
    save_property(socket, socket.assigns.live_action, property_params)
  end

  defp save_property(socket, :edit, property_params) do
    case Properties.update_property(
           socket.assigns.current_scope,
           socket.assigns.property,
           property_params
         ) do
      {:ok, property} ->
        {:noreply,
         socket
         |> put_flash(:info, "Property updated successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, property)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_property(socket, :new, property_params) do
    case Properties.create_property(socket.assigns.current_scope, property_params) do
      {:ok, property} ->
        {:noreply,
         socket
         |> put_flash(:info, "Property created successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, property)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _property), do: ~p"/properties"
  defp return_path(_scope, "show", property), do: ~p"/properties/#{property}"
end
