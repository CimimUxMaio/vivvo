defmodule VivvoWeb.PropertyLive.Show do
  @moduledoc """
  LiveView for displaying property details with contract and payment information.

  Shows property information, active contract details if present,
  and allows owners to accept or reject pending payments.
  """
  use VivvoWeb, :live_view

  alias Vivvo.Contracts
  alias Vivvo.Properties

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6 sm:space-y-8">
        <%!-- Page Header --%>
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h1 class="text-2xl sm:text-3xl font-bold tracking-tight text-base-content">
              Property {@property.name}
            </h1>
            <p class="mt-1 text-sm text-base-content/70">
              {@property.address}
            </p>
          </div>
          <div class="flex items-center gap-2">
            <.button navigate={~p"/properties"}>
              <.icon name="hero-arrow-left" class="w-5 h-5" />
            </.button>
            <.button variant="primary" navigate={~p"/properties/#{@property}/edit?return_to=show"}>
              <.icon name="hero-pencil-square" class="w-5 h-5 mr-1" /> Edit
            </.button>
          </div>
        </div>

        <%!-- Main Two-Column Layout --%>
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <%!-- Left Sidebar: Property Summary Card (1/3 width on desktop) --%>
          <div class="lg:col-span-1">
            <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 p-6 lg:sticky lg:top-6">
              <%!-- Hero Icon --%>
              <div class="flex justify-center mb-6">
                <div class="w-24 h-24 rounded-full bg-primary/10 flex items-center justify-center">
                  <.icon name="hero-building-office" class="w-12 h-12 text-primary" />
                </div>
              </div>

              <%!-- Property Name --%>
              <div class="text-center mb-4">
                <h2 class="text-xl sm:text-2xl font-bold text-base-content break-words">
                  {@property.name}
                </h2>
              </div>

              <%!-- Property Address --%>
              <div class="text-center mb-6">
                <p class="text-sm text-base-content/70 flex items-center justify-center gap-2">
                  <.icon name="hero-map-pin" class="w-4 h-4 flex-shrink-0" />
                  <span class="break-words">{@property.address}</span>
                </p>
              </div>

              <%!-- Specification Badges --%>
              <div class="flex flex-wrap items-center justify-center gap-3 mb-6">
                <%= if @property.area do %>
                  <div class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-base-200 rounded-full text-sm">
                    <.icon name="hero-square-3-stack-3d" class="w-4 h-4 text-base-content/60" />
                    <span class="font-medium">{@property.area} m²</span>
                  </div>
                <% end %>

                <%= if @property.rooms do %>
                  <div class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-base-200 rounded-full text-sm">
                    <.icon name="hero-home" class="w-4 h-4 text-base-content/60" />
                    <span class="font-medium">{@property.rooms} rooms</span>
                  </div>
                <% end %>
              </div>

              <%!-- Notes Preview --%>
              <%= if @property.notes && @property.notes != "" do %>
                <div class="pt-4 border-t border-base-200">
                  <div class="flex items-start gap-2">
                    <.icon
                      name="hero-document-text"
                      class="w-4 h-4 text-base-content/50 flex-shrink-0 mt-0.5"
                    />
                    <p class="text-sm text-base-content/70 line-clamp-4">
                      {@property.notes}
                    </p>
                  </div>
                </div>
              <% end %>

              <%!-- Empty State Hint --%>
              <%= if !@property.area && !@property.rooms && (!@property.notes || @property.notes == "") do %>
                <div class="pt-4 border-t border-base-200">
                  <p class="text-xs text-base-content/50 text-center">
                    No additional details available
                  </p>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Right Side: Tabbed Content (2/3 width on desktop) --%>
          <div class="lg:col-span-2">
            <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200">
              <%!-- Tab Navigation --%>
              <div class="flex items-center gap-1 p-2 border-b border-base-200 overflow-x-auto">
                <button
                  phx-click="switch_tab"
                  phx-value-tab="details"
                  class={[
                    "px-4 py-2 rounded-lg text-sm font-medium transition-all duration-200 whitespace-nowrap",
                    "hover:bg-base-200/50 focus:outline-none focus:ring-2 focus:ring-primary/20",
                    @active_tab == "details" &&
                      [
                        "bg-primary/10 text-primary",
                        "ring-1 ring-primary/20"
                      ],
                    @active_tab != "details" && "text-base-content/70 hover:text-base-content"
                  ]}
                >
                  <div class="flex items-center gap-2">
                    <.icon name="hero-information-circle" class="w-4 h-4" /> Property Details
                  </div>
                </button>

                <button
                  phx-click="switch_tab"
                  phx-value-tab="active_contract"
                  class={[
                    "px-4 py-2 rounded-lg text-sm font-medium transition-all duration-200 whitespace-nowrap",
                    "hover:bg-base-200/50 focus:outline-none focus:ring-2 focus:ring-primary/20",
                    @active_tab == "active_contract" &&
                      [
                        "bg-primary/10 text-primary",
                        "ring-1 ring-primary/20"
                      ],
                    @active_tab != "active_contract" && "text-base-content/70 hover:text-base-content"
                  ]}
                >
                  <div class="flex items-center gap-2">
                    <.icon name="hero-document-text" class="w-4 h-4" /> Active Contract
                    <%= if @contract do %>
                      <span class={[
                        "w-2 h-2 rounded-full",
                        Contracts.contract_status(@contract) == :active && "bg-success",
                        Contracts.contract_status(@contract) == :upcoming && "bg-info"
                      ]}>
                      </span>
                    <% end %>
                  </div>
                </button>

                <button
                  phx-click="switch_tab"
                  phx-value-tab="contract_history"
                  class={[
                    "px-4 py-2 rounded-lg text-sm font-medium transition-all duration-200 whitespace-nowrap",
                    "hover:bg-base-200/50 focus:outline-none focus:ring-2 focus:ring-primary/20",
                    @active_tab == "contract_history" &&
                      [
                        "bg-primary/10 text-primary",
                        "ring-1 ring-primary/20"
                      ],
                    @active_tab != "contract_history" &&
                      "text-base-content/70 hover:text-base-content"
                  ]}
                >
                  <div class="flex items-center gap-2">
                    <.icon name="hero-clock" class="w-4 h-4" /> Contract History
                    <%= if @historic_contracts != [] do %>
                      <span class="px-1.5 py-0.5 bg-base-200 rounded-full text-xs">
                        {length(@historic_contracts)}
                      </span>
                    <% end %>
                  </div>
                </button>
              </div>

              <%!-- Tab Content --%>
              <div class="p-6">
                <%= case @active_tab do %>
                  <% "details" -> %>
                    <.property_details_tab property={@property} />
                  <% "active_contract" -> %>
                    <.active_contract_tab contract={@contract} property={@property} />
                  <% "contract_history" -> %>
                    <.contract_history_tab
                      historic_contracts={@historic_contracts}
                      property={@property}
                    />
                <% end %>
              </div>
            </div>
          </div>
        </div>
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

  # Property Details Tab Component
  defp property_details_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Section Header --%>
      <div class="flex items-center gap-2 pb-4 border-b border-base-200">
        <div class="p-1.5 bg-primary/10 rounded-lg">
          <.icon name="hero-information-circle" class="w-5 h-5 text-primary" />
        </div>
        <h3 class="text-lg font-semibold text-base-content">Property Information</h3>
      </div>

      <%!-- Details Grid --%>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-6">
        <%!-- Name --%>
        <div class="space-y-2">
          <label class="text-sm font-medium text-base-content/60">Property Name</label>
          <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
            <.icon name="hero-building-office" class="w-5 h-5 text-base-content/50" />
            <span class="font-medium text-base-content">{@property.name}</span>
          </div>
        </div>

        <%!-- Address --%>
        <div class="space-y-2">
          <label class="text-sm font-medium text-base-content/60">Address</label>
          <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
            <.icon name="hero-map-pin" class="w-5 h-5 text-base-content/50" />
            <span class="font-medium text-base-content">{@property.address}</span>
          </div>
        </div>

        <%!-- Area --%>
        <div class="space-y-2">
          <label class="text-sm font-medium text-base-content/60">Area</label>
          <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
            <.icon name="hero-square-3-stack-3d" class="w-5 h-5 text-base-content/50" />
            <span class="font-medium text-base-content">
              <%= if @property.area do %>
                {@property.area} m²
              <% else %>
                Not specified
              <% end %>
            </span>
          </div>
        </div>

        <%!-- Rooms --%>
        <div class="space-y-2">
          <label class="text-sm font-medium text-base-content/60">Rooms</label>
          <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
            <.icon name="hero-home" class="w-5 h-5 text-base-content/50" />
            <span class="font-medium text-base-content">
              <%= if @property.rooms do %>
                {@property.rooms} rooms
              <% else %>
                Not specified
              <% end %>
            </span>
          </div>
        </div>
      </div>

      <%!-- Notes Section --%>
      <div class="space-y-2">
        <label class="text-sm font-medium text-base-content/60">Notes</label>
        <div class="p-4 bg-base-200/50 rounded-lg">
          <%= if @property.notes && @property.notes != "" do %>
            <div class="flex items-start gap-3">
              <.icon
                name="hero-document-text"
                class="w-5 h-5 text-base-content/50 flex-shrink-0 mt-0.5"
              />
              <p class="text-base-content/80 whitespace-pre-wrap">{@property.notes}</p>
            </div>
          <% else %>
            <div class="flex items-center gap-3 text-base-content/50">
              <.icon name="hero-document-text" class="w-5 h-5" />
              <span>No notes available for this property.</span>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Active Contract Tab Component
  defp active_contract_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <%= if @contract do %>
        <%!-- Section Header with Status --%>
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 pb-4 border-b border-base-200">
          <div class="flex items-center gap-2">
            <div class="p-1.5 bg-success/10 rounded-lg">
              <.icon name="hero-document-text" class="w-5 h-5 text-success" />
            </div>
            <h3 class="text-lg font-semibold text-base-content">Active Contract</h3>
          </div>
          <.contract_status_badge status={Contracts.contract_status(@contract)} />
        </div>

        <%!-- Tenant Information --%>
        <div class="bg-base-200/30 rounded-xl p-5">
          <h4 class="text-sm font-medium text-base-content/60 mb-4">Current Tenant</h4>
          <div class="flex items-center gap-4">
            <div class="w-14 h-14 rounded-full bg-primary/10 flex items-center justify-center">
              <span class="text-lg font-bold text-primary">
                {String.first(@contract.tenant.first_name)}{String.first(@contract.tenant.last_name)}
              </span>
            </div>
            <div>
              <p class="text-lg font-semibold text-base-content">
                {@contract.tenant.first_name} {@contract.tenant.last_name}
              </p>
              <p class="text-sm text-base-content/60">
                {@contract.tenant.email}
              </p>
            </div>
          </div>
        </div>

        <%!-- Contract Details Grid --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <%!-- Monthly Rent --%>
          <div class="space-y-2">
            <label class="text-sm font-medium text-base-content/60">Monthly Rent</label>
            <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
              <.icon name="hero-banknotes" class="w-5 h-5 text-base-content/50" />
              <span class="font-semibold text-base-content">
                {format_currency(Contracts.current_rent_value(@contract))}
              </span>
            </div>
          </div>

          <%!-- Contract Status --%>
          <div class="space-y-2">
            <label class="text-sm font-medium text-base-content/60">Status</label>
            <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
              <.icon name="hero-check-circle" class="w-5 h-5 text-base-content/50" />
              <.contract_status_badge status={Contracts.contract_status(@contract)} />
            </div>
          </div>

          <%!-- Start Date --%>
          <div class="space-y-2">
            <label class="text-sm font-medium text-base-content/60">Start Date</label>
            <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
              <.icon name="hero-calendar" class="w-5 h-5 text-base-content/50" />
              <span class="font-medium text-base-content">
                {format_date(@contract.start_date)}
              </span>
            </div>
          </div>

          <%!-- End Date --%>
          <div class="space-y-2">
            <label class="text-sm font-medium text-base-content/60">End Date</label>
            <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
              <.icon name="hero-calendar" class="w-5 h-5 text-base-content/50" />
              <span class="font-medium text-base-content">
                {format_date(@contract.end_date)}
              </span>
            </div>
          </div>
        </div>

        <%!-- Duration Badge --%>
        <div class="flex items-center gap-2 p-3 bg-info/10 rounded-lg border border-info/20">
          <.icon name="hero-clock" class="w-5 h-5 text-info" />
          <span class="text-sm text-base-content/80">
            Contract duration: {calculate_duration(@contract.start_date, @contract.end_date)}
          </span>
        </div>

        <%!-- Actions --%>
        <div class="flex flex-col sm:flex-row items-stretch sm:items-center gap-3 pt-4 border-t border-base-200">
          <.button phx-click="show_contract_modal" class="flex-1 sm:flex-none">
            <.icon name="hero-eye" class="w-5 h-5 mr-1" /> View Full Details
          </.button>
        </div>
      <% else %>
        <%!-- Empty State --%>
        <div class="text-center py-12">
          <div class="w-20 h-20 rounded-full bg-base-200 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-document-text" class="w-10 h-10 text-base-content/30" />
          </div>
          <h3 class="text-lg font-semibold text-base-content mb-2">No Active Contract</h3>
          <p class="text-sm text-base-content/60 mb-6 max-w-sm mx-auto">
            This property doesn't have an active contract. Create one to start managing tenants and rent payments.
          </p>
          <.button variant="primary" navigate={~p"/properties/#{@property}/contracts/new"}>
            <.icon name="hero-plus" class="w-5 h-5 mr-2" /> Create Contract
          </.button>
        </div>
      <% end %>
    </div>
    """
  end

  # Contract History Tab Component
  defp contract_history_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Section Header --%>
      <div class="flex items-center gap-2 pb-4 border-b border-base-200">
        <div class="p-1.5 bg-info/10 rounded-lg">
          <.icon name="hero-clock" class="w-5 h-5 text-info" />
        </div>
        <h3 class="text-lg font-semibold text-base-content">Contract History</h3>
      </div>

      <%= if @historic_contracts != [] do %>
        <div class="space-y-4">
          <%= for contract <- @historic_contracts do %>
            <div class="bg-base-200/30 rounded-xl p-5 hover:bg-base-200/50 transition-colors">
              <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
                <%!-- Tenant Info --%>
                <div class="flex items-center gap-4">
                  <div class="w-12 h-12 rounded-full bg-base-300 flex items-center justify-center">
                    <span class="text-sm font-bold text-base-content/70">
                      {String.first(contract.tenant.first_name)}{String.first(
                        contract.tenant.last_name
                      )}
                    </span>
                  </div>
                  <div>
                    <p class="font-semibold text-base-content">
                      {contract.tenant.first_name} {contract.tenant.last_name}
                    </p>
                    <p class="text-sm text-base-content/60">{contract.tenant.email}</p>
                  </div>
                </div>

                <%!-- Contract Details --%>
                <div class="flex flex-col items-start sm:items-end gap-2">
                  <.contract_status_badge status={:expired} />
                  <div class="flex items-center gap-2 text-sm text-base-content/60">
                    <.icon name="hero-calendar" class="w-4 h-4" />
                    {format_date(contract.start_date)} - {format_date(contract.end_date)}
                  </div>
                </div>
              </div>

              <%!-- Contract Stats --%>
              <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 mt-4 pt-4 border-t border-base-300/50">
                <div>
                  <p class="text-xs text-base-content/50 mb-1">Monthly Rent</p>
                  <p class="font-medium text-base-content">
                    {format_currency(Contracts.current_rent_value(contract))}
                  </p>
                </div>
                <div>
                  <p class="text-xs text-base-content/50 mb-1">Duration</p>
                  <p class="font-medium text-base-content">
                    {calculate_duration(contract.start_date, contract.end_date)}
                  </p>
                </div>
                <div>
                  <p class="text-xs text-base-content/50 mb-1">Start Date</p>
                  <p class="font-medium text-base-content">{format_date(contract.start_date)}</p>
                </div>
                <div>
                  <p class="text-xs text-base-content/50 mb-1">End Date</p>
                  <p class="font-medium text-base-content">{format_date(contract.end_date)}</p>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% else %>
        <%!-- Empty State --%>
        <div class="text-center py-12">
          <div class="w-20 h-20 rounded-full bg-base-200 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-clock" class="w-10 h-10 text-base-content/30" />
          </div>
          <h3 class="text-lg font-semibold text-base-content mb-2">No Contract History</h3>
          <p class="text-sm text-base-content/60 mb-6 max-w-sm mx-auto">
            This property doesn't have any past contracts. When contracts expire, they will appear here.
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper function to calculate contract duration
  defp calculate_duration(start_date, end_date) do
    days = Date.diff(end_date, start_date)
    months = div(days, 30)
    years = div(months, 12)
    remaining_months = rem(months, 12)

    cond do
      years > 0 && remaining_months > 0 -> "#{years}y #{remaining_months}m"
      years > 0 -> "#{years} year#{if years > 1, do: "s"}"
      months > 0 -> "#{months} month#{if months > 1, do: "s"}"
      true -> "#{days} day#{if days > 1, do: "s"}"
    end
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Properties.subscribe_properties(socket.assigns.current_scope)
      Contracts.subscribe_contracts(socket.assigns.current_scope)
    end

    scope = socket.assigns.current_scope
    property = Properties.get_property!(scope, id)
    contract = Contracts.current_contract_for_property(scope, property.id)

    # Fetch historic contracts (past contracts for this property)
    historic_contracts = fetch_historic_contracts(scope, property.id, contract)

    {:ok,
     socket
     |> assign(:page_title, "Show Property")
     |> assign(:property, property)
     |> assign(:contract, contract)
     |> assign(:historic_contracts, historic_contracts)
     |> assign(:active_tab, "details")
     |> assign(:show_contract_modal, false)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
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
    contract = Vivvo.Repo.preload(contract, [:tenant, :payments, :rent_periods])

    {:noreply,
     socket
     |> assign(:contract, contract)
     |> assign(
       :historic_contracts,
       fetch_historic_contracts(socket.assigns.current_scope, property_id, contract)
     )}
  end

  def handle_info(
        {:updated, %Vivvo.Contracts.Contract{property_id: property_id} = contract},
        socket
      )
      when property_id == socket.assigns.property.id do
    contract = Vivvo.Repo.preload(contract, [:tenant, :payments, :rent_periods])

    {:noreply,
     socket
     |> assign(:contract, contract)
     |> assign(
       :historic_contracts,
       fetch_historic_contracts(socket.assigns.current_scope, property_id, contract)
     )}
  end

  def handle_info({:deleted, %Vivvo.Contracts.Contract{property_id: property_id}}, socket)
      when property_id == socket.assigns.property.id do
    {:noreply,
     socket
     |> assign(:contract, nil)
     |> assign(
       :historic_contracts,
       fetch_historic_contracts(socket.assigns.current_scope, property_id, nil)
     )}
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

  # Handle payment events - refresh contract data
  def handle_info(
        {_action, %Vivvo.Payments.Payment{contract_id: contract_id}},
        %{assigns: %{contract: %{id: id}}} = socket
      )
      when contract_id == id do
    {:noreply, refresh_contract_data(socket)}
  end

  def handle_info({_action, %Vivvo.Payments.Payment{}}, socket) do
    {:noreply, socket}
  end

  # Helper Functions

  defp refresh_contract_data(socket) do
    scope = socket.assigns.current_scope
    contract = Contracts.current_contract_for_property(scope, socket.assigns.property.id)

    socket
    |> assign(:contract, contract)
    |> assign(
      :historic_contracts,
      fetch_historic_contracts(scope, socket.assigns.property.id, contract)
    )
  end

  # Fetch historic contracts (past contracts that are no longer active)
  # NOTE: Currently returns mock data for demonstration
  # In production, replace with actual database query to fetch expired contracts
  defp fetch_historic_contracts(_scope, _property_id, _current_contract) do
    [
      %{
        id: 1,
        tenant: %{
          first_name: "John",
          last_name: "Doe",
          email: "john.doe@example.com"
        },
        start_date: ~D[2022-01-01],
        end_date: ~D[2023-01-01],
        rent_periods: [
          %{amount: Decimal.new("1200.00"), start_date: ~D[2022-01-01]}
        ]
      },
      %{
        id: 2,
        tenant: %{
          first_name: "Jane",
          last_name: "Smith",
          email: "jane.smith@example.com"
        },
        start_date: ~D[2020-06-01],
        end_date: ~D[2021-06-01],
        rent_periods: [
          %{amount: Decimal.new("1100.00"), start_date: ~D[2020-06-01]}
        ]
      }
    ]
  end
end
