defmodule VivvoWeb.PropertyLive.Show do
  use VivvoWeb, :live_view

  alias Vivvo.Contracts
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

      <%!-- CONTRACT SECTION --%>
      <div class="mt-8">
        <.header>
          Contract Information
          <:actions>
            <%= if @contract do %>
              <.button phx-click="show_contract_modal">
                <.icon name="hero-eye" /> View Details
              </.button>
              <.button
                variant="primary"
                navigate={~p"/properties/#{@property}/contracts/#{@contract}/edit"}
              >
                <.icon name="hero-pencil-square" /> Edit Contract
              </.button>
            <% else %>
              <.button variant="primary" navigate={~p"/properties/#{@property}/contracts/new"}>
                <.icon name="hero-plus" /> Create Contract
              </.button>
            <% end %>
          </:actions>
        </.header>

        <%= if @contract do %>
          <.list>
            <:item title="Tenant">
              {@contract.tenant.first_name} {@contract.tenant.last_name}
            </:item>
            <:item title="Monthly Rent">
              {format_currency(@contract.rent)}
            </:item>
            <:item title="Status">
              <.contract_status_badge status={Contracts.contract_status(@contract)} />
            </:item>
          </.list>
        <% else %>
          <p class="text-gray-500 mt-4">No active contract for this property.</p>
        <% end %>
      </div>

      <%!-- CONTRACT MODAL --%>
      <%= if @show_contract_modal && @contract do %>
        <.live_component
          module={VivvoWeb.ContractLive.ShowModal}
          id="contract-modal"
          contract={@contract}
          property={@property}
          current_scope={@current_scope}
        />
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Properties.subscribe_properties(socket.assigns.current_scope)
      Contracts.subscribe_contracts(socket.assigns.current_scope)
    end

    property = Properties.get_property!(socket.assigns.current_scope, id)
    contract = Contracts.get_contract_for_property(socket.assigns.current_scope, property.id)

    {:ok,
     socket
     |> assign(:page_title, "Show Property")
     |> assign(:property, property)
     |> assign(:contract, contract)
     |> assign(:show_contract_modal, false)}
  end

  @impl true
  def handle_event("show_contract_modal", _params, socket) do
    {:noreply, assign(socket, :show_contract_modal, true)}
  end

  @impl true
  def handle_info(:close_contract_modal, socket) do
    {:noreply, assign(socket, :show_contract_modal, false)}
  end

  def handle_info(
        {:created, %Vivvo.Contracts.Contract{property_id: property_id} = contract},
        socket
      )
      when property_id == socket.assigns.property.id do
    # Preload tenant if not already loaded
    contract = Vivvo.Repo.preload(contract, :tenant)
    {:noreply, assign(socket, :contract, contract)}
  end

  def handle_info(
        {:updated, %Vivvo.Contracts.Contract{property_id: property_id} = contract},
        socket
      )
      when property_id == socket.assigns.property.id do
    # Preload tenant if not already loaded
    contract = Vivvo.Repo.preload(contract, :tenant)
    {:noreply, assign(socket, :contract, contract)}
  end

  def handle_info({:deleted, %Vivvo.Contracts.Contract{property_id: property_id}}, socket)
      when property_id == socket.assigns.property.id do
    {:noreply, assign(socket, :contract, nil)}
  end

  # Ignore contract events for other properties
  def handle_info({_action, %Vivvo.Contracts.Contract{}}, socket) do
    {:noreply, socket}
  end

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
