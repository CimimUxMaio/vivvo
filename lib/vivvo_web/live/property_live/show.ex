defmodule VivvoWeb.PropertyLive.Show do
  @moduledoc """
  LiveView for displaying property details with contract and payment information.

  Shows property information, active contract details if present,
  and allows owners to accept or reject pending payments.
  """
  use VivvoWeb, :live_view

  import VivvoWeb.Helpers.ContractHelpers

  alias Vivvo.Contracts
  alias Vivvo.Payments
  alias Vivvo.Properties

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6 sm:space-y-8">
        <%!-- Page Header --%>
        <.page_header title={"Property #{@property.name}"} back_navigate={~p"/properties"}>
          <:subtitle>
            {@property.address}
          </:subtitle>

          <:action>
            <.button variant="primary" navigate={~p"/properties/#{@property}/edit?return_to=show"}>
              <.icon name="hero-pencil-square" class="w-5 h-5 mr-1" /> Edit
            </.button>

            <.button variant="primary" navigate={~p"/properties/#{@property}/contracts/new"}>
              <.icon name="hero-plus" class="w-5 h-5 mr-2" /> Create Contract
            </.button>
          </:action>
        </.page_header>

        <%!-- Main Two-Column Layout --%>
        <div class="grid grid-cols-1 lg:grid-cols-5 gap-6">
          <%!-- Left Sidebar: Property Summary Card (40% width on desktop) --%>
          <div class="lg:col-span-2">
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

          <%!-- Right Side: Tabbed Content (60% width on desktop) --%>
          <div class="lg:col-span-3">
            <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200">
              <%!-- Tab Navigation --%>
              <div class="p-3 border-b border-base-200">
                <.sliding_selector
                  value={@active_tab}
                  on_select="switch_tab"
                >
                  <:option value="active_contract">
                    <span class="flex items-center gap-1">
                      <.icon name="hero-document-text" class="w-4 h-4" />
                      <span>Active Contract</span>
                      <%= if @contract do %>
                        <span class={[
                          "w-1.5 h-1.5 rounded-full",
                          Contracts.contract_status(@contract) == :active && "bg-success",
                          Contracts.contract_status(@contract) == :upcoming && "bg-info"
                        ]}>
                        </span>
                      <% end %>
                    </span>
                  </:option>
                  <:option value="contract_history">
                    <span class="flex items-center gap-1">
                      <.icon name="hero-clock" class="w-4 h-4" />
                      <span>Contract History</span>
                      <%= if @contracts != [] do %>
                        <span class="text-xs">
                          ({length(@contracts)})
                        </span>
                      <% end %>
                    </span>
                  </:option>
                </.sliding_selector>
              </div>

              <%!-- Tab Content --%>
              <div class="p-6">
                <%= case @active_tab do %>
                  <% "active_contract" -> %>
                    <.active_contract_tab contract={@contract} property={@property} />
                  <% "contract_history" -> %>
                    <.contract_history_tab
                      contracts={@contracts}
                      property={@property}
                    />
                  <% _ -> %>
                    <.active_contract_tab contract={@contract} property={@property} />
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Active Contract Tab Component
  defp active_contract_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <%= if @contract do %>
        <%!-- Section Header with Status --%>
        <div class="flex items-center justify-between gap-4 pb-4 border-b border-base-200">
          <div class="flex items-center gap-2">
            <div class="p-1.5 bg-success/10 rounded-lg flex items-center justify-center">
              <.icon name="hero-document-text" class="w-5 h-5 text-success" />
            </div>
            <h3 class="text-lg font-semibold text-base-content">Active Contract</h3>
          </div>
          <.button navigate={
            ~p"/properties/#{@property.id}/contracts/#{@contract.id}?return_to=contract"
          }>
            <.icon name="hero-eye" class="w-5 h-5" />
            <span class="hidden sm:block">View Full Details</span>
          </.button>
        </div>

        <%!-- Contract Details Grid --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <%!-- Current Tenant --%>
          <div class="space-y-2">
            <label class="text-sm font-medium text-base-content/60">Current Tenant</label>
            <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
              <div class="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
                <span class="text-xs font-bold text-primary">
                  {String.first(@contract.tenant.first_name)}{String.first(@contract.tenant.last_name)}
                </span>
              </div>
              <div class="min-w-0">
                <p class="font-medium text-base-content text-sm truncate">
                  {@contract.tenant.first_name} {@contract.tenant.last_name}
                </p>
                <p class="text-xs text-base-content/60 truncate">
                  {@contract.tenant.email}
                </p>
              </div>
            </div>
          </div>

          <%!-- Monthly Rent --%>
          <div class="space-y-2">
            <label class="text-sm font-medium text-base-content/60">Monthly Rent</label>
            <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
              <.icon name="hero-banknotes" class="w-5 h-5 text-base-content/50" />
              <span class="font-semibold text-base-content flex items-center gap-2">
                {format_currency(Contracts.current_rent_value(@contract))}
                <%= if @contract.index_type do %>
                  <span class="inline-flex items-center gap-1 px-2 py-0.5 bg-info/10 text-info rounded-full text-xs font-medium">
                    <.icon name="hero-arrow-trending-up" class="w-3 h-3" /> Indexed
                  </span>
                <% end %>
              </span>
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

          <%!-- Payment Due --%>
          <div class="space-y-2">
            <label class="text-sm font-medium text-base-content/60">Payment Due</label>
            <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
              <.icon name="hero-calendar-days" class="w-5 h-5 text-base-content/50" />
              <span class="font-medium text-base-content">
                Day {@contract.expiration_day} of each month
              </span>
            </div>
          </div>

          <%!-- Indexing Information (only shown when contract has indexing) --%>
          <%= if @contract.index_type do %>
            <%!-- Index Type --%>
            <div class="space-y-2">
              <label class="text-sm font-medium text-base-content/60">Index Type</label>
              <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
                <.icon name="hero-arrow-trending-up" class="w-5 h-5 text-base-content/50" />
                <span class="font-medium text-base-content">
                  {index_type_label(@contract.index_type)}
                </span>
              </div>
            </div>

            <%!-- Update Frequency --%>
            <div class="space-y-2">
              <label class="text-sm font-medium text-base-content/60">Update Frequency</label>
              <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
                <.icon name="hero-arrow-path" class="w-5 h-5 text-base-content/50" />
                <span class="font-medium text-base-content">
                  {rent_period_duration_label(@contract.rent_period_duration)}
                </span>
              </div>
            </div>

            <%!-- Next Rent Update --%>
            <.next_rent_update_field contract={@contract} />
          <% end %>
        </div>

        <%!-- Contract Notes --%>
        <%= if @contract.notes && @contract.notes != "" do %>
          <div class="space-y-2">
            <label class="text-sm font-medium text-base-content/60">Notes</label>
            <div class="p-4 bg-base-200/50 rounded-lg">
              <div class="flex items-start gap-3">
                <.icon
                  name="hero-document-text"
                  class="w-5 h-5 text-base-content/50 flex-shrink-0 mt-0.5"
                />
                <p class="text-sm text-base-content/80 whitespace-pre-wrap">{@contract.notes}</p>
              </div>
            </div>
          </div>
        <% end %>
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
          <.button
            variant="primary"
            navigate={~p"/properties/#{@property}/contracts/new"}
            id="create-contract-empty-state"
          >
            <.icon name="hero-plus" class="w-5 h-5 mr-2" /> Create Contract
          </.button>
        </div>
      <% end %>
    </div>
    """
  end

  # Contract History Tab Component
  defp contract_history_tab(assigns) do
    configs =
      assigns
      |> Map.get(:contracts, [])
      |> Enum.map(&{&1.id, contract_timeline_config(Contracts.contract_status(&1))})
      |> Map.new()

    assigns = assign(assigns, :configs, configs)

    ~H"""
    <div class="space-y-6">
      <%!-- Section Header --%>
      <div class="flex items-center gap-2 pb-4 border-b border-base-200">
        <div class="p-1.5 flex items-center justify-center bg-info/10 rounded-lg">
          <.icon name="hero-clock" class="w-5 h-5 text-info" />
        </div>
        <h3 class="text-lg font-semibold text-base-content">Contract History</h3>
      </div>

      <%= if @contracts != [] do %>
        <div class="bg-base-200 rounded-xl">
          <.timeline_container>
            <:timeline_item
              :for={contract <- @contracts}
              status={@configs[contract.id].status}
              icon={@configs[contract.id].icon}
              label={"#{contract.tenant.first_name} #{contract.tenant.last_name}"}
            >
              <%!-- Header: Avatar, Tenant Info, Status & Button - Desktop: side-by-side, Mobile: stacked --%>
              <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
                <div class="flex items-start gap-3">
                  <%!-- Tenant Avatar --%>
                  <div
                    class="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0 mt-0.5"
                    title={"#{contract.tenant.first_name} #{contract.tenant.last_name}"}
                    aria-label={"Avatar for #{contract.tenant.first_name} #{contract.tenant.last_name}"}
                  >
                    <span class="text-xs font-bold text-primary">
                      {String.first(contract.tenant.first_name)}{String.first(
                        contract.tenant.last_name
                      )}
                    </span>
                  </div>

                  <%!-- Tenant Info --%>
                  <div class="flex-1 min-w-0">
                    <p class="font-semibold text-base-content text-sm sm:text-base break-words">
                      {contract.tenant.first_name} {contract.tenant.last_name}
                    </p>
                    <p class="text-xs text-base-content/60 break-all">
                      {contract.tenant.email}
                    </p>
                  </div>
                </div>

                <%!-- Status Badge & View Button --%>
                <div class="flex items-center gap-2 flex-shrink-0">
                  <.contract_status_badge status={Contracts.contract_status(contract)} />
                  <.button
                    navigate={
                      ~p"/properties/#{@property.id}/contracts/#{contract.id}?return_to=history"
                    }
                    aria-label="View contract"
                  >
                    <.icon name="hero-eye" class="w-5 h-5" />
                    <span class="hidden sm:block">View</span>
                  </.button>
                </div>
              </div>

              <%!-- Contract Period --%>
              <div class="flex flex-col gap-1 text-sm text-base-content/70 pt-3 border-t border-base-200 mt-3">
                <div class="flex items-center gap-2">
                  <.icon name="hero-calendar" class="w-4 h-4 flex-shrink-0" />
                  <span>
                    {format_date(contract.start_date)} - {format_date(contract.end_date)}
                  </span>
                </div>
                <span class="text-base-content/50 text-xs pl-6">
                  {format_duration(contract.start_date, contract.end_date)}
                </span>
              </div>

              <%!-- Contract Details: Rent & Payment - Stacked on mobile, side-by-side on desktop --%>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-3 border-t border-base-200 mt-3">
                <%!-- Monthly Rent --%>
                <div class="flex items-center justify-between sm:block">
                  <p class="text-xs text-base-content/50 sm:mb-0.5">Monthly Rent</p>
                  <p class="font-semibold text-base-content">
                    {format_currency(Contracts.current_rent_value(contract))}
                  </p>
                </div>

                <%!-- Payment Due --%>
                <div class="flex items-center justify-between sm:block">
                  <p class="text-xs text-base-content/50 sm:mb-0.5">Payment Due</p>
                  <p class="font-medium text-base-content text-sm">
                    Day {contract.expiration_day}
                  </p>
                </div>
              </div>

              <%!-- Indexing Indicator (if applicable) --%>
              <%= if contract.index_type do %>
                <div class="pt-3 border-t border-base-200 mt-3">
                  <div class="flex flex-col gap-2">
                    <span class="inline-flex items-center gap-1 px-2 py-0.5 bg-info/10 text-info rounded-full text-xs font-medium w-fit">
                      <.icon name="hero-arrow-trending-up" class="w-3 h-3" /> Indexed
                    </span>
                    <span class="text-xs text-base-content/50 break-words">
                      {index_type_label(contract.index_type)}
                    </span>
                  </div>
                </div>
              <% end %>
            </:timeline_item>
          </.timeline_container>
        </div>
      <% else %>
        <%!-- Empty State --%>
        <div class="text-center py-12">
          <div class="w-20 h-20 rounded-full bg-base-200 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-clock" class="w-10 h-10 text-base-content/30" />
          </div>
          <h3 class="text-lg font-semibold text-base-content mb-2">No Contracts</h3>
          <p class="text-sm text-base-content/60 mb-6 max-w-sm mx-auto">
            This property doesn't have any contracts yet. Create one to start managing tenants and rent payments.
          </p>
          <.button variant="primary" navigate={~p"/properties/#{@property}/contracts/new"}>
            <.icon name="hero-plus" class="w-5 h-5 mr-2" /> Create Contract
          </.button>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Properties.subscribe_properties(socket.assigns.current_scope)
      Contracts.subscribe_contracts(socket.assigns.current_scope)
      Payments.subscribe_payments(socket.assigns.current_scope)
    end

    {:ok, assign_data(socket, id)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = Map.get(params, "tab", "contract")
    active_tab = if tab == "history", do: "contract_history", else: "active_contract"

    {:noreply, assign(socket, :active_tab, active_tab)}
  end

  @impl true
  def handle_event("switch_tab", %{"selected" => tab}, socket)
      when tab in ["active_contract", "contract_history"] do
    tab_param = if tab == "contract_history", do: "history", else: "contract"

    {:noreply,
     push_patch(socket, to: ~p"/properties/#{socket.assigns.property.id}?tab=#{tab_param}")}
  end

  # Assigns all data for the property show page
  defp assign_data(socket, property_id) do
    scope = socket.assigns.current_scope
    property = Properties.get_property!(scope, property_id)
    contracts = Contracts.list_property_contracts(scope, property_id)
    current_contract = Contracts.current_contract_for_property(scope, property_id)

    socket
    |> assign(:page_title, "Show Property")
    |> assign(:property, property)
    |> assign(:contracts, contracts)
    |> assign(:contract, current_contract)
  end

  # Refreshes all property data when an update is received
  # Preserves user state (active tab) to avoid disrupting the UI
  defp refresh_data(socket) do
    active_tab = socket.assigns.active_tab

    socket
    |> assign_data(socket.assigns.property.id)
    |> assign(:active_tab, active_tab)
  end

  @impl true
  # Property events - refresh when this property changes
  def handle_info(
        {:updated, %Vivvo.Properties.Property{id: id}},
        %{assigns: %{property: %{id: id}}} = socket
      ) do
    {:noreply, refresh_data(socket)}
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

  def handle_info({_action, %Vivvo.Properties.Property{}}, socket) do
    {:noreply, socket}
  end

  # Contract events - refresh when any contract for this property changes
  def handle_info(
        {_action, %Vivvo.Contracts.Contract{property_id: property_id}},
        %{assigns: %{property: %{id: id}}} = socket
      )
      when property_id == id do
    {:noreply, refresh_data(socket)}
  end

  def handle_info({_action, %Vivvo.Contracts.Contract{}}, socket) do
    {:noreply, socket}
  end

  # Payment events - refresh when any payment for this property's contracts changes
  def handle_info(
        {_action, %Vivvo.Payments.Payment{contract_id: contract_id}},
        %{assigns: %{contracts: contracts}} = socket
      ) do
    # Check if payment belongs to any of this property's contracts
    if Enum.any?(contracts, &(&1.id == contract_id)) do
      {:noreply, refresh_data(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({_action, %Vivvo.Payments.Payment{}}, socket) do
    {:noreply, socket}
  end
end
