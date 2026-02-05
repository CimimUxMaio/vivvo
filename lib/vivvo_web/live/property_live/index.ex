defmodule VivvoWeb.PropertyLive.Index do
  use VivvoWeb, :live_view

  alias Vivvo.Properties

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Listing Properties
        <:actions>
          <.button variant="primary" navigate={~p"/properties/new"}>
            <.icon name="hero-plus" /> New Property
          </.button>
        </:actions>
      </.header>

      <.table
        id="properties"
        rows={@streams.properties}
        row_click={fn {_id, property} -> JS.navigate(~p"/properties/#{property}") end}
      >
        <:col :let={{_id, property}} label="Name">{property.name}</:col>
        <:col :let={{_id, property}} label="Address">{property.address}</:col>
        <:col :let={{_id, property}} label="Area">{property.area}</:col>
        <:col :let={{_id, property}} label="Rooms">{property.rooms}</:col>
        <:col :let={{_id, property}} label="Notes">{property.notes}</:col>
        <:action :let={{_id, property}}>
          <div class="sr-only">
            <.link navigate={~p"/properties/#{property}"}>Show</.link>
          </div>
          <.link navigate={~p"/properties/#{property}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, property}}>
          <.link
            phx-click={JS.push("delete", value: %{id: property.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Properties.subscribe_properties(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Properties")
     |> stream(:properties, list_properties(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    property = Properties.get_property!(socket.assigns.current_scope, id)
    {:ok, _} = Properties.delete_property(socket.assigns.current_scope, property)

    {:noreply, stream_delete(socket, :properties, property)}
  end

  @impl true
  def handle_info({type, %Vivvo.Properties.Property{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, stream(socket, :properties, list_properties(socket.assigns.current_scope), reset: true)}
  end

  defp list_properties(current_scope) do
    Properties.list_properties(current_scope)
  end
end
