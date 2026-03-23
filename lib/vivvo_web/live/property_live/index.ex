defmodule VivvoWeb.PropertyLive.Index do
  @moduledoc """
  LiveView for listing and managing properties.

  Displays a table of all properties with options to view, edit, and delete.
  Uses LiveView streams for efficient rendering of property lists.
  Features an enhanced data table design with status badges and responsive layouts.
  """
  use VivvoWeb, :live_view

  alias Vivvo.Contracts
  alias Vivvo.Contracts.Contract
  alias Vivvo.Properties
  alias Vivvo.Properties.Property

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6 sm:space-y-8">
        <%!-- Page Header --%>
        <.page_header title="Properties" back_navigate={~p"/"}>
          <:subtitle>Manage your rental properties and track their occupancy status.</:subtitle>
          <:action>
            <.button variant="primary" navigate={~p"/properties/new"}>
              <.icon name="hero-plus" class="w-5 h-5 mr-2" /> New Property
            </.button>
          </:action>
        </.page_header>

        <%!-- Properties Table Container --%>
        <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 overflow-hidden">
          <%= if !@properties_empty? do %>
            <%!-- Desktop/Tablet Table --%>
            <div class="hidden sm:block overflow-x-auto">
              <table class="w-full text-sm">
                <thead class="bg-base-200/50">
                  <tr>
                    <th class="px-4 py-3 text-left text-xs font-medium text-base-content/70">
                      Property
                    </th>
                    <th class="px-4 py-3 text-center text-xs font-medium text-base-content/70">
                      Status
                    </th>
                    <th class="px-4 py-3 text-center text-xs font-medium text-base-content/70">
                      Area
                    </th>
                    <th class="px-4 py-3 text-center text-xs font-medium text-base-content/70">
                      Rooms
                    </th>
                    <th class="hidden lg:table-cell px-4 py-3 text-left text-xs font-medium text-base-content/70">
                      Notes
                    </th>
                    <th class="px-4 py-3 text-center text-xs font-medium text-base-content/70">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody id="properties" phx-update="stream" class="divide-y divide-base-200">
                  <tr
                    :for={{id, property} <- @streams.properties}
                    id={id}
                    class="hover:bg-base-200/30 transition-colors group cursor-pointer"
                    phx-click={JS.push("show-property", value: %{id: property.id})}
                    role="button"
                    tabindex="0"
                    phx-keydown={JS.push("show-property", value: %{id: property.id})}
                    phx-key="enter"
                  >
                    <%!-- Property Name & Address --%>
                    <td class="px-4 py-4">
                      <div class="flex items-center gap-3">
                        <div class="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center flex-shrink-0">
                          <.icon name="hero-building-office" class="w-5 h-5 text-primary" />
                        </div>
                        <div class="min-w-0">
                          <p class="font-semibold text-base-content truncate">
                            {property.name}
                          </p>
                          <p class="text-xs text-base-content/50 truncate max-w-[200px]">
                            {property.address}
                          </p>
                        </div>
                      </div>
                    </td>

                    <%!-- Status Badge --%>
                    <td class="px-4 py-4 text-center">
                      <.status_badge status={@property_statuses[property.id]} />
                    </td>

                    <%!-- Area --%>
                    <td class="px-4 py-4 text-center">
                      <div class="flex items-center justify-center gap-1.5 text-base-content/70">
                        <.icon name="hero-square-3-stack-3d" class="w-4 h-4" />
                        <span class="font-medium">{property.area} m²</span>
                      </div>
                    </td>

                    <%!-- Rooms --%>
                    <td class="px-4 py-4 text-center">
                      <div class="flex items-center justify-center gap-1.5 text-base-content/70">
                        <.icon name="hero-home" class="w-4 h-4" />
                        <span class="font-medium">{property.rooms}</span>
                      </div>
                    </td>

                    <%!-- Notes - Hidden on tablet --%>
                    <td class="hidden lg:table-cell px-4 py-4">
                      <%= if property.notes != "" do %>
                        <p
                          class="text-xs text-base-content/60 truncate max-w-[150px]"
                          title={property.notes}
                        >
                          {property.notes}
                        </p>
                      <% else %>
                        <span class="text-xs text-base-content/30">-</span>
                      <% end %>
                    </td>

                    <%!-- Actions --%>
                    <td class="px-4 py-4" phx-stop>
                      <div class="flex items-center justify-center gap-1">
                        <.link
                          navigate={~p"/properties/#{property}/edit"}
                          class="btn btn-ghost btn-md btn-square"
                          title="Edit"
                        >
                          <.icon name="hero-pencil" class="w-5 h-5" />
                        </.link>
                        <button
                          phx-click={JS.push("delete", value: %{id: property.id})}
                          data-confirm="Are you sure you want to delete this property?"
                          class="btn btn-ghost btn-md btn-square text-error hover:text-error"
                          title="Delete"
                        >
                          <.icon name="hero-trash" class="w-5 h-5" />
                        </button>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <%!-- Mobile Card Layout --%>
            <div class="sm:hidden divide-y divide-base-200" id="properties-mobile" phx-update="stream">
              <div
                :for={{id, property} <- @streams.properties}
                id={"#{id}-mobile"}
                class="p-4 hover:bg-base-200/30 transition-colors cursor-pointer"
                phx-click={JS.push("show-property", value: %{id: property.id})}
              >
                <%!-- Card Header: Icon + Name + Status --%>
                <div class="flex items-start justify-between gap-3 mb-3">
                  <div class="flex items-center gap-3 min-w-0">
                    <div class="w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center flex-shrink-0">
                      <.icon name="hero-building-office" class="w-6 h-6 text-primary" />
                    </div>
                    <div class="min-w-0">
                      <p class="font-semibold text-base-content truncate">
                        {property.name}
                      </p>
                      <p class="text-xs text-base-content/50 truncate">
                        {property.address}
                      </p>
                    </div>
                  </div>
                  <.status_badge status={@property_statuses[property.id]} />
                </div>

                <%!-- Card Details: Area & Rooms --%>
                <div class="flex items-center gap-4 mb-3 text-sm">
                  <div class="flex items-center gap-1.5 text-base-content/70">
                    <.icon name="hero-square-3-stack-3d" class="w-4 h-4" />
                    <span>{property.area} m²</span>
                  </div>
                  <div class="flex items-center gap-1.5 text-base-content/70">
                    <.icon name="hero-home" class="w-4 h-4" />
                    <span>{property.rooms} rooms</span>
                  </div>
                </div>

                <%!-- Card Notes --%>
                <%= if property.notes && property.notes != "" do %>
                  <p class="text-xs text-base-content/60 mb-3 line-clamp-2">
                    {property.notes}
                  </p>
                <% end %>

                <%!-- Card Actions --%>
                <div class="flex items-center gap-2 pt-3 border-t border-base-200" phx-stop>
                  <.link
                    navigate={~p"/properties/#{property}/edit"}
                    class="btn btn-outline btn-sm flex-1"
                  >
                    <.icon name="hero-pencil" class="w-4 h-4 mr-1" /> Edit
                  </.link>
                  <button
                    phx-click={JS.push("delete", value: %{id: property.id})}
                    data-confirm="Are you sure you want to delete this property?"
                    class="btn btn-error btn-outline btn-sm flex-1"
                  >
                    <.icon name="hero-trash" class="w-4 h-4 mr-1" /> Delete
                  </button>
                </div>
              </div>
            </div>
          <% else %>
            <%!-- Empty State --%>
            <div class="p-12 text-center">
              <div class="w-20 h-20 rounded-full bg-base-200 flex items-center justify-center mx-auto mb-4">
                <.icon name="hero-building-office" class="w-10 h-10 text-base-content/30" />
              </div>
              <h3 class="text-lg font-semibold text-base-content mb-1">No properties found</h3>
              <p class="text-sm text-base-content/60 mb-6">
                Get started by adding your first property to manage.
              </p>
              <.button variant="primary" navigate={~p"/properties/new"}>
                <.icon name="hero-plus" class="w-5 h-5 mr-2" /> Add Property
              </.button>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Status Badge Component
  defp status_badge(assigns) do
    ~H"""
    <%= case @status do %>
      <% :occupied -> %>
        <div class="inline-flex items-center gap-1.5 px-2.5 py-1 bg-success/10 text-success rounded-full text-xs font-medium border border-success/20">
          <.icon name="hero-check-circle" class="w-3.5 h-3.5" />
          <span>Occupied</span>
        </div>
      <% :upcoming -> %>
        <div class="inline-flex items-center gap-1.5 px-2.5 py-1 bg-info/10 text-info rounded-full text-xs font-medium border border-info/20">
          <.icon name="hero-clock" class="w-3.5 h-3.5" />
          <span>Upcoming</span>
        </div>
      <% _ -> %>
        <div class="inline-flex items-center gap-1.5 px-2.5 py-1 bg-base-300/30 text-base-content/60 rounded-full text-xs font-medium border border-base-300/50">
          <.icon name="hero-home" class="w-3.5 h-3.5" />
          <span>Vacant</span>
        </div>
    <% end %>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    properties = list_properties(socket.assigns.current_scope)
    property_statuses = build_property_statuses(properties)

    if connected?(socket) do
      Properties.subscribe_properties(socket.assigns.current_scope)
      Contracts.subscribe_contracts(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Properties")
     |> assign(:property_statuses, property_statuses)
     |> assign(:properties_empty?, properties == [])
     |> stream(:properties, properties)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    property = Properties.get_property!(socket.assigns.current_scope, id)

    case Properties.delete_property(socket.assigns.current_scope, property) do
      {:ok, _} ->
        property_statuses = Map.delete(socket.assigns.property_statuses, property.id)

        {:noreply,
         socket
         |> stream_delete(:properties, property)
         |> assign(:property_statuses, property_statuses)
         |> assign(:properties_empty?, map_size(property_statuses) == 0)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete property")}
    end
  end

  @impl true
  def handle_event("show-property", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/properties/#{id}")}
  end

  @impl true
  def handle_info({type, %Property{user_id: user_id}}, socket)
      when type in [:created, :updated, :deleted] do
    # Only process messages for properties belonging to current user
    if user_id == socket.assigns.current_scope.user.id do
      properties = list_properties(socket.assigns.current_scope)
      property_statuses = build_property_statuses(properties)

      {:noreply,
       socket
       |> assign(:property_statuses, property_statuses)
       |> assign(:properties_empty?, properties == [])
       |> stream(:properties, properties, reset: true)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({type, %Contract{user_id: user_id}}, socket)
      when type in [:created, :updated, :deleted] do
    # Only process messages for contracts belonging to current user
    if user_id == socket.assigns.current_scope.user.id do
      properties = list_properties(socket.assigns.current_scope)
      property_statuses = build_property_statuses(properties)

      {:noreply,
       socket
       |> assign(:property_statuses, property_statuses)
       |> assign(:properties_empty?, properties == [])
       |> stream(:properties, properties, reset: true)}
    else
      {:noreply, socket}
    end
  end

  defp list_properties(current_scope) do
    Properties.list_properties(current_scope, preload: [:contract])
  end

  defp build_property_statuses(properties) do
    properties
    |> Enum.map(fn property ->
      {property.id, get_property_status(property)}
    end)
    |> Map.new()
  end

  defp get_property_status(%Property{contract: nil}), do: :vacant

  defp get_property_status(%Property{contract: contract}) when not is_nil(contract) do
    case Contracts.contract_status(contract) do
      :active -> :occupied
      :upcoming -> :upcoming
      _ -> :vacant
    end
  end
end
