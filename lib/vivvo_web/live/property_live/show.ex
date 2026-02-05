defmodule VivvoWeb.PropertyLive.Show do
  use VivvoWeb, :live_view

  alias Vivvo.Properties

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Property {@property.id}
        <:subtitle>This is a property record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/properties"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/properties/#{@property}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit property
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@property.name}</:item>
        <:item title="Address">{@property.address}</:item>
        <:item title="Area">{@property.area}</:item>
        <:item title="Rooms">{@property.rooms}</:item>
        <:item title="Notes">{@property.notes}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Properties.subscribe_properties(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Property")
     |> assign(:property, Properties.get_property!(socket.assigns.current_scope, id))}
  end

  @impl true
  def handle_info(
        {:updated, %Vivvo.Properties.Property{id: id} = property},
        %{assigns: %{property: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :property, property)}
  end

  def handle_info(
        {:deleted, %Vivvo.Properties.Property{id: id}},
        %{assigns: %{property: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current property was deleted.")
     |> push_navigate(to: ~p"/properties")}
  end

  def handle_info({type, %Vivvo.Properties.Property{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end
end
