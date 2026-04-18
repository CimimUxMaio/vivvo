defmodule VivvoWeb.TenantDashboardLive do
  @moduledoc """
  Tenant dashboard LiveView showing contract details and payment history.
  """
  use VivvoWeb, :live_view

  import VivvoWeb.Helpers.ContractHelpers
  import VivvoWeb.PaymentComponents, only: [file_chip: 1]

  alias Vivvo.Contracts
  alias Vivvo.Payments

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    # Subscribe to payments for real-time updates
    if connected?(socket) do
      Payments.subscribe_payments(scope)
    end

    {:ok,
     socket
     |> assign(:contracts, [])
     |> assign(:selected_contract, nil)
     |> assign(:current_expanded, true)
     |> assign(:history_expanded, false)
     |> assign(:expanded_payment_items, MapSet.new())
     |> assign(:payment_contract, nil)
     |> assign(:payment_month, nil)
     |> assign(:payment_type, :rent)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    scope = socket.assigns.current_scope
    contracts = Contracts.list_contracts_for_tenant(scope)

    # Select contract based on URL param or default to first
    selected_contract =
      case params["property"] do
        nil ->
          List.first(contracts)

        contract_id ->
          Enum.find(contracts, &(to_string(&1.id) == contract_id)) || List.first(contracts)
      end

    socket =
      socket
      |> assign(:contracts, contracts)
      |> assign(:selected_contract, selected_contract)
      |> assign(:current_expanded, true)
      |> assign(:history_expanded, false)
      |> assign_contract_details(scope, selected_contract)

    {:noreply, socket}
  end

  defp assign_contract_details(socket, _scope, nil) do
    socket
    |> assign(:contract, nil)
    |> assign(:contract_status, nil)
    |> assign(:payment_status, nil)
    |> assign(:total_due, nil)
    |> assign(:earliest_due, nil)
    |> assign(:payment_statuses, [])
    |> assign(:next_due_date, nil)
    |> assign(:contract_needs_update, false)
  end

  defp assign_contract_details(socket, scope, contract) do
    socket
    |> assign(:contract, contract)
    |> assign(:contract_status, Contracts.contract_status(contract))
    |> assign(:payment_status, Contracts.contract_payment_status(scope, contract))
    |> assign(:total_due, Contracts.total_amount_due(scope, contract))
    |> assign(:earliest_due, Contracts.earliest_due_date(scope, contract))
    |> assign(:payment_statuses, Contracts.get_payment_statuses(scope, contract))
    |> assign(:next_due_date, Contracts.next_payment_date(contract))
    |> assign(:contract_needs_update, Contracts.needs_update?(contract))
  end

  # PubSub handlers for real-time payment updates
  @impl true
  def handle_info({event, %Vivvo.Payments.Payment{}}, socket)
      when event in [:created, :updated, :deleted] do
    scope = socket.assigns.current_scope
    {:noreply, refresh_tenant_contracts(socket, scope)}
  end

  @impl true
  def handle_info({:flash, type, message}, socket) do
    {:noreply, put_flash(socket, type, message)}
  end

  @impl true
  def handle_event("select_contract", %{"id" => contract_id}, socket) do
    # Verify the contract belongs to this tenant
    if Enum.any?(socket.assigns.contracts, &(to_string(&1.id) == contract_id)) do
      {:noreply, push_patch(socket, to: ~p"/tenant/dashboard?property=#{contract_id}")}
    else
      {:noreply, put_flash(socket, :error, "Invalid property selection")}
    end
  end

  @impl true
  def handle_event("toggle_history", _params, socket) do
    {:noreply, update(socket, :history_expanded, &(&1 == false))}
  end

  @impl true
  def handle_event("toggle_current", _params, socket) do
    {:noreply, update(socket, :current_expanded, &(&1 == false))}
  end

  @impl true
  def handle_event("toggle_payment_item", %{"payment_number" => payment_num}, socket) do
    expanded = socket.assigns.expanded_payment_items
    num = String.to_integer(payment_num)

    new_expanded =
      if MapSet.member?(expanded, num) do
        MapSet.delete(expanded, num)
      else
        MapSet.put(expanded, num)
      end

    {:noreply, assign(socket, :expanded_payment_items, new_expanded)}
  end

  @impl true
  def handle_event(
        "show_payment_modal",
        %{"contract-id" => contract_id, "month" => month},
        socket
      ) do
    scope = socket.assigns.current_scope
    contract = Contracts.get_contract_for_tenant(scope, contract_id)

    if contract do
      {month_num, _} = Integer.parse(month)

      {:noreply,
       socket
       |> assign(:payment_contract, contract)
       |> assign(:payment_month, month_num)
       |> assign(:payment_type, :rent)
       |> push_modal_open("payment-modal")}
    else
      {:noreply, put_flash(socket, :error, "Contract not found")}
    end
  end

  @impl true
  def handle_event(
        "show_misc_payment_modal",
        %{"contract_id" => contract_id},
        socket
      ) do
    scope = socket.assigns.current_scope
    contract = Contracts.get_contract_for_tenant(scope, contract_id)

    if contract do
      {:noreply,
       socket
       |> assign(:payment_contract, contract)
       |> assign(:payment_month, nil)
       |> assign(:payment_type, :miscellaneous)
       |> push_modal_open("payment-modal")}
    else
      {:noreply, put_flash(socket, :error, "Contract not found")}
    end
  end

  defp refresh_tenant_contracts(socket, scope) do
    contracts = Contracts.list_contracts_for_tenant(scope)

    selected_contract =
      if socket.assigns.selected_contract do
        Enum.find(
          contracts,
          &(to_string(&1.id) == to_string(socket.assigns.selected_contract.id))
        ) ||
          List.first(contracts)
      else
        List.first(contracts)
      end

    socket
    |> assign(:contracts, contracts)
    |> assign(:selected_contract, selected_contract)
    |> assign_contract_details(scope, selected_contract)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-8">
        <%= if @contracts != [] do %>
          <%!-- Page Header with New Misc Payment Action --%>
          <.page_header title="My Rentals" back_navigate={nil}>
            <:action
              icon="hero-plus"
              label="New Payment"
              phx-click="show_misc_payment_modal"
              rest={["phx-value-contract_id": @contract.id]}
            />
          </.page_header>

          <%!-- Property Switcher for Multiple Contracts --%>
          <%= if length(@contracts) > 1 do %>
            <.property_switcher contracts={@contracts} selected_contract={@selected_contract} />
          <% end %>

          <%!-- A. Header: Current Situation Snapshot --%>
          <.situation_snapshot
            contract={@contract}
            contract_status={@contract_status}
            payment_status={@payment_status}
            total_due={@total_due}
            earliest_due={@earliest_due}
            next_due_date={@next_due_date}
          />

          <%!-- Rent Update Warning (shown when contract needs update) --%>
          <%= if @contract_needs_update do %>
            <.rent_update_warning />
          <% end %>

          <%!-- B. Payments Overview --%>
          <.payments_overview
            contract={@contract}
            payment_statuses={@payment_statuses}
            scope={@current_scope}
            current_expanded={@current_expanded}
            history_expanded={@history_expanded}
            expanded_payment_items={@expanded_payment_items}
            contract_needs_update={@contract_needs_update}
          />

          <%!-- C. Contract & Property Quick Access --%>
          <.contract_quick_access contract={@contract} contract_status={@contract_status} />

          <%!-- Submit Payment Modal - LiveComponent always mounted, visibility via JS --%>
          <.live_component
            module={VivvoWeb.SubmitPaymentModal}
            id="payment-modal"
            contract={@payment_contract}
            type={@payment_type}
            month={@payment_month}
            current_scope={@current_scope}
          />
        <% else %>
          <.no_contract_message />
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # Property Switcher Component (for multiple contracts)
  defp property_switcher(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl p-4 sm:p-5 shadow-sm border border-base-200">
      <%!-- Header --%>
      <div class="flex items-center gap-2 mb-3 sm:mb-4">
        <div class="p-1.5 bg-primary/10 rounded-lg">
          <.icon name="hero-squares-2x2" class="w-4 h-4 text-primary" />
        </div>
        <span class="text-sm font-medium text-base-content/70">Your Properties</span>
        <span class="ml-auto text-xs text-base-content/50">
          {length(@contracts)} active
        </span>
      </div>

      <%!-- Horizontal Scrollable Property Cards --%>
      <div class="flex -mx-4 px-4 pt-1 overflow-x-auto scrollbar-hide gap-3 pb-1">
        <%= for contract <- @contracts do %>
          <% is_selected = @selected_contract && @selected_contract.id == contract.id %>
          <button
            phx-click="select_contract"
            phx-value-id={contract.id}
            class={[
              "group relative flex-shrink-0 flex items-center gap-3 p-3 min-w-[220px] max-w-[280px] rounded-xl text-left transition-all duration-200",
              "border-2 hover:shadow-md hover:-translate-y-0.5 hover:cursor-pointer",
              is_selected &&
                [
                  "bg-primary/5 border-primary shadow-sm",
                  "ring-1 ring-primary/20"
                ],
              !is_selected &&
                [
                  "bg-base-200/50 border-transparent hover:bg-base-200 hover:border-base-300"
                ]
            ]}
          >
            <%!-- Property Icon/Avatar --%>
            <div class={[
              "w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 transition-colors",
              is_selected && "bg-primary text-primary-content",
              !is_selected && "bg-base-300/50 text-base-content/60 group-hover:bg-base-300"
            ]}>
              <.icon name="hero-building-office" class="w-5 h-5" />
            </div>

            <%!-- Property Info --%>
            <div class="flex-1 min-w-0">
              <p class={[
                "font-semibold truncate text-sm",
                is_selected && "text-primary",
                !is_selected && "text-base-content"
              ]}>
                {contract.property.name}
              </p>
              <p class="text-xs text-base-content/50 truncate">
                {contract.property.address}
              </p>
            </div>

            <%!-- Selection Indicator --%>
            <div class={[
              "w-5 h-5 rounded-full border-2 flex items-center justify-center transition-all duration-200 flex-shrink-0",
              is_selected &&
                [
                  "border-primary bg-primary scale-110",
                  "shadow-sm shadow-primary/30"
                ],
              !is_selected && "border-base-300 bg-transparent group-hover:border-base-400"
            ]}>
              <%= if is_selected do %>
                <.icon name="hero-check" class="w-3 h-3 text-primary-content" />
              <% end %>
            </div>
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  # Rent Update Warning Component
  defp rent_update_warning(assigns) do
    ~H"""
    <div class="p-4 bg-warning/10 rounded-lg border border-warning/20">
      <div class="flex items-start gap-3">
        <.icon name="hero-clock" class="w-5 h-5 text-warning flex-shrink-0 mt-0.5" />
        <div>
          <p class="text-sm font-medium text-warning">
            Rent update in progress
          </p>
          <p class="text-sm text-base-content/70">
            Your rent is being recalculated for the new period. Rent payment submissions are temporarily disabled. Please check back shortly.
          </p>
        </div>
      </div>
    </div>
    """
  end

  # Situation Snapshot Component (Header)
  defp situation_snapshot(assigns) do
    current_period = Calendar.strftime(Date.utc_today(), "%B %Y")

    status_label =
      case assigns.payment_status do
        :paid -> "Nothing Due"
        :overdue -> "Overdue Payment"
        _ -> "Nothing Due"
      end

    days_until_next =
      if assigns.next_due_date do
        Date.diff(assigns.next_due_date, Date.utc_today())
      else
        nil
      end

    assigns =
      assign(assigns,
        current_period: current_period,
        status_label: status_label,
        days_until_next: days_until_next
      )

    ~H"""
    <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 overflow-hidden">
      <%!-- Top Bar: Property & Period --%>
      <div class="px-6 py-4 border-b border-base-200 bg-base-200/30">
        <div class="flex items-center justify-between gap-3">
          <div class="flex items-center gap-3 min-w-0 flex-1">
            <div class="p-2 bg-primary/10 rounded-lg flex-shrink-0">
              <.icon name="hero-building-office" class="w-5 h-5 text-primary" />
            </div>
            <div class="min-w-0">
              <h1 class="text-lg font-bold text-base-content truncate">{@contract.property.name}</h1>
              <p class="text-sm text-base-content/60 truncate">{@contract.property.address}</p>
            </div>
          </div>
          <div class="flex items-center gap-2 flex-shrink-0">
            <.contract_status_badge status={@contract_status} />
          </div>
        </div>
      </div>

      <%!-- Primary Status Card --%>
      <div class="p-6">
        <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-6">
          <%!-- Left: Amount Due with Status Badge --%>
          <div class="flex-1">
            <div class="flex items-center gap-3 mb-1">
              <p class="text-sm text-base-content/60">Total Amount Due</p>
              <span class={[
                "inline-flex px-2 py-1 rounded-full text-xs font-medium",
                @payment_status in [:paid, :on_time, :upcoming] && "bg-success/10 text-success",
                @payment_status == :overdue && "bg-error/10 text-error"
              ]}>
                {@status_label}
              </span>
            </div>
            <p class={[
              "text-4xl sm:text-5xl font-bold tracking-tight",
              Decimal.gt?(@total_due, Decimal.new(0)) && "text-error",
              Decimal.lte?(@total_due, Decimal.new(0)) && "text-success"
            ]}>
              {format_currency(@total_due)}
            </p>
            <%= if @earliest_due do %>
              <p class="text-sm text-base-content/60 mt-2">
                Due by <span class="font-medium text-base-content">{format_date(@earliest_due)}</span>
              </p>
            <% end %>
          </div>
        </div>

        <%!-- Success Message with Next Payment Date (when paid up) --%>
        <%= if Decimal.lte?(@total_due, Decimal.new(0)) do %>
          <div class="mt-6 pt-6 border-t border-base-200">
            <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
              <div class="flex items-center gap-2 text-success">
                <.icon name="hero-check-circle" class="w-5 h-5" />
                <span class="font-medium">All payments are up to date!</span>
              </div>

              <%= if @next_due_date do %>
                <div
                  id="upcoming-payments"
                  class="flex items-center gap-2 text-sm text-base-content/70 sm:ml-4"
                >
                  <.icon name="hero-calendar" class="w-4 h-4" />
                  <span>Next due {format_date(@next_due_date)}</span>
                  <span class="text-base-content/50">({format_time_until(@days_until_next)})</span>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Payments Overview Component
  defp payments_overview(assigns) do
    # Separate into categories
    unpaid_items = Enum.filter(assigns.payment_statuses, &(&1.status != :paid))
    paid_items = Enum.filter(assigns.payment_statuses, &(&1.status == :paid))

    has_unpaid = unpaid_items != []

    assigns =
      assign(assigns,
        unpaid_items: unpaid_items,
        paid_items: paid_items,
        has_unpaid: has_unpaid
      )

    ~H"""
    <div class="flex flex-col gap-8">
      <%!-- Current & Unpaid Payments (Expanded by Default) --%>
      <%= if @has_unpaid do %>
        <div
          class="bg-base-100 rounded-2xl shadow-sm border border-base-200 overflow-hidden"
          id="current-payments"
        >
          <button
            phx-click="toggle_current"
            class="w-full px-6 py-4 flex items-center justify-between hover:bg-warning/10 hover:cursor-pointer transition-colors bg-warning/5"
          >
            <div class="flex items-center gap-2">
              <.icon name="hero-clock" class="w-5 h-5 text-warning" />
              <h2 class="text-lg font-semibold">Current & Unpaid</h2>
              <span class="px-2 py-1 bg-warning/10 text-warning rounded-full text-xs font-medium">
                {length(@unpaid_items)} pending
              </span>
            </div>
            <.icon
              name="hero-chevron-down"
              class={[
                "w-5 h-5 text-base-content/50 transition-transform",
                @current_expanded && "rotate-180"
              ]}
            />
          </button>

          <%!-- Animated content container --%>
          <div class={[
            "overflow-hidden transition-all duration-300 ease-in-out",
            @current_expanded && "max-h-[600px] opacity-100 overflow-y-auto scrollbar-hide",
            !@current_expanded && "max-h-0 opacity-0"
          ]}>
            <div class="divide-y divide-base-200 border-t border-base-200">
              <%= for item <- @unpaid_items do %>
                <.payment_overview_item
                  item={item}
                  contract={@contract}
                  scope={@scope}
                  expanded_items={@expanded_payment_items}
                  contract_needs_update={@contract_needs_update}
                />
              <% end %>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Payment History (Collapsed by Default) --%>
      <%= if @paid_items != [] do %>
        <div
          class="bg-base-100 rounded-2xl shadow-sm border border-base-200 overflow-hidden"
          id="payment-history"
        >
          <button
            phx-click="toggle_history"
            class="w-full px-6 py-4 flex items-center justify-between hover:bg-base-200/50 hover:cursor-pointer transition-colors"
          >
            <div class="flex items-center gap-2">
              <.icon name="hero-check-circle" class="w-5 h-5 text-success" />
              <h2 class="text-lg font-semibold">Payment History</h2>
              <span class="px-2 py-1 bg-success/10 text-success rounded-full text-xs font-medium">
                {length(@paid_items)} paid
              </span>
            </div>
            <.icon
              name="hero-chevron-down"
              class={[
                "w-5 h-5 text-base-content/50 transition-transform",
                @history_expanded && "rotate-180"
              ]}
            />
          </button>

          <%!-- Animated content container --%>
          <div class={[
            "overflow-hidden transition-all duration-300 ease-in-out",
            @history_expanded && "max-h-[600px] opacity-100 overflow-y-auto scrollbar-hide",
            !@history_expanded && "max-h-0 opacity-0"
          ]}>
            <div class="divide-y divide-base-200 border-t border-base-200">
              <%= for item <- @paid_items do %>
                <.payment_overview_item
                  item={item}
                  contract={@contract}
                  scope={@scope}
                  show_actions={false}
                  expanded_items={@expanded_payment_items}
                />
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Payment Overview Item Component
  defp payment_overview_item(assigns) do
    show_actions = Map.get(assigns, :show_actions, true)
    contract_needs_update = Map.get(assigns, :contract_needs_update, false)

    can_submit =
      assigns.item.status in [:unpaid, :partial] && show_actions && not contract_needs_update

    is_expanded = MapSet.member?(assigns.expanded_items, assigns.item.payment_number)
    has_payments = assigns.item.payments != []
    payment_count = length(assigns.item.payments)

    visuals = payment_item_visuals(assigns.item, assigns.contract)

    assigns =
      assign(assigns,
        show_actions: show_actions,
        can_submit: can_submit,
        is_expanded: is_expanded,
        has_payments: has_payments,
        payment_count: payment_count,
        icon: visuals.icon,
        icon_bg: visuals.bg_color,
        icon_color: visuals.text_color
      )

    ~H"""
    <div class="group">
      <%!-- Clickable Header Row --%>
      <div
        phx-click="toggle_payment_item"
        phx-value-payment_number={@item.payment_number}
        class={[
          "px-6 py-4 cursor-pointer transition-colors duration-200",
          "hover:bg-base-200/30",
          @is_expanded && "bg-base-200/20"
        ]}
      >
        <%!-- Grid Layout for consistent alignment --%>
        <div class="flex flex-col sm:grid sm:grid-cols-[1fr_auto_auto_auto] gap-3 sm:gap-4 sm:items-center">
          <%!-- Left: Period Info --%>
          <div class="flex items-start gap-4 min-w-0">
            <%!-- Status Icon --%>
            <div class={[
              "w-12 h-12 rounded-xl flex items-center justify-center flex-shrink-0",
              @icon_bg
            ]}>
              <.icon name={@icon} class={["w-6 h-6", @icon_color]} />
            </div>

            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 flex-wrap">
                <p class="font-semibold">Month {@item.payment_number}</p>

                <.month_status_badge status={@item.status} />

                <%= if @item.is_overdue do %>
                  <span class="px-2 py-0.5 bg-error/10 text-error rounded-full text-xs font-medium">
                    Overdue
                  </span>
                <% end %>

                <%!-- Payment count indicator (only when payments exist) --%>
                <%= if @has_payments do %>
                  <span class="hidden sm:block">
                    <.payment_count_indicator
                      payment_count={@payment_count}
                      is_expanded={@is_expanded}
                      variant={:desktop}
                    />
                  </span>

                  <span class="sm:hidden">
                    <.payment_count_indicator
                      payment_count={@payment_count}
                      is_expanded={@is_expanded}
                      variant={:mobile}
                    />
                  </span>
                <% end %>
              </div>

              <p class="text-sm text-base-content/60 mt-0.5">
                Due: {format_date(@item.due_date)}
              </p>
            </div>
          </div>

          <%!-- Mobile: Actions row (inline with space-between) --%>
          <div class="flex sm:hidden items-center justify-between gap-3">
            <%!-- Mini Invoice Breakdown --%>
            <div>
              <div class="flex items-center gap-2 text-xs">
                <span class="text-base-content/60">Rent:</span>
                <span class="font-medium">{format_currency(@item.rent)}</span>
              </div>
              <div class="flex items-center gap-2 text-xs">
                <span class="text-base-content/60">Paid:</span>
                <span class={[
                  "font-medium",
                  Decimal.gt?(@item.total_paid, Decimal.new(0)) && "text-success"
                ]}>
                  {format_currency(@item.total_paid)}
                </span>
              </div>
              <%= if @item.status != :paid do %>
                <div class="flex items-center gap-2 text-xs mt-0.5 pt-0.5 border-t border-base-200">
                  <span class="text-base-content/60">Remaining:</span>
                  <span class="font-semibold text-error">
                    {format_currency(Decimal.sub(@item.rent, @item.total_paid))}
                  </span>
                </div>
              <% end %>
            </div>

            <%!-- Pay Button (always visible when applicable) --%>
            <.payment_submit_button
              :if={@can_submit}
              contract_id={@contract.id}
              month={@item.payment_number}
              class="flex-shrink-0"
            />
          </div>

          <%!-- Desktop: Mini Invoice Breakdown --%>
          <div class="hidden sm:block text-right">
            <div class="flex items-center gap-2 text-sm">
              <span class="text-base-content/60">Rent:</span>
              <span class="font-medium">{format_currency(@item.rent)}</span>
            </div>
            <div class="flex items-center gap-2 text-sm">
              <span class="text-base-content/60">Paid:</span>
              <span class={[
                "font-medium",
                Decimal.gt?(@item.total_paid, Decimal.new(0)) && "text-success"
              ]}>
                {format_currency(@item.total_paid)}
              </span>
            </div>
            <%= if @item.status != :paid do %>
              <div class="flex items-center gap-2 text-sm mt-1 pt-1 border-t border-base-200">
                <span class="text-base-content/60">Remaining:</span>
                <span class="font-semibold text-error">
                  {format_currency(Decimal.sub(@item.rent, @item.total_paid))}
                </span>
              </div>
            <% end %>
          </div>

          <%!-- Desktop: Pay Button (always visible when applicable) --%>
          <div class="hidden sm:block flex-shrink-0">
            <.payment_submit_button
              :if={@can_submit}
              contract_id={@contract.id}
              month={@item.payment_number}
            />
          </div>

          <%!-- Desktop: Expansion Toggle Icon (or placeholder for alignment) --%>
          <div class="hidden sm:flex w-8 h-8 flex-shrink-0 items-center justify-center">
            <%= if @has_payments do %>
              <div class={[
                "w-8 h-8 rounded-full flex items-center justify-center",
                "transition-all duration-200",
                @is_expanded && "bg-primary/10 rotate-180",
                !@is_expanded && "bg-base-200 group-hover:bg-base-300"
              ]}>
                <.icon
                  name="hero-chevron-down"
                  class={[
                    "w-5 h-5 transition-colors",
                    @is_expanded && "text-primary",
                    !@is_expanded && "text-base-content/50"
                  ]}
                />
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Expandable Timeline Section --%>
      <%= if @has_payments do %>
        <div class={[
          "overflow-hidden transition-all duration-300 ease-in-out",
          "bg-base-200 border-t border-base-300",
          @is_expanded && "max-h-[600px] opacity-100",
          !@is_expanded && "max-h-0 opacity-0"
        ]}>
          <div class="space-y-2 py-4 sm:py-6">
            <%!-- Timeline Header --%>
            <div class="flex items-center justify-between px-4 sm:px-6">
              <h4 class="text-sm font-medium text-base-content/70 flex items-center gap-2">
                <.icon name="hero-clock" class="w-4 h-4" /> Payment Timeline
              </h4>
              <span class="text-xs text-base-content/50">
                {@payment_count} payment{if @payment_count > 1, do: "s"} total
              </span>
            </div>

            <%!-- Timeline Items using timeline_container component --%>
            <.timeline_container gap={:sm}>
              <:timeline_item
                :for={
                  {payment, config} <-
                    Enum.map(@item.payments, &{&1, payment_timeline_config(&1.status)})
                }
                status={config.status}
                icon={config.icon}
                label={config.label}
              >
                <%!-- Header: Amount & Date --%>
                <div class="flex items-start justify-between gap-2 mb-2">
                  <div>
                    <p class="font-semibold text-base">
                      {format_currency(payment.amount)}
                    </p>
                    <p class="text-xs text-base-content/50">
                      {payment.inserted_at |> Calendar.strftime("%b %d, %Y at %I:%M %p")}
                    </p>
                  </div>
                  <.payment_badge status={payment.status} size={:sm} />
                </div>

                <%!-- Rejection Reason (if applicable) --%>
                <%= if payment.rejection_reason && payment.rejection_reason != "" do %>
                  <div class="mt-2 p-2 bg-error/10 rounded-lg border border-error/20">
                    <p class="text-xs text-error">
                      <span class="font-medium">Rejected:</span> {payment.rejection_reason}
                    </p>
                  </div>
                <% end %>

                <%!-- Notes --%>
                <%= if payment.notes && payment.notes != "" do %>
                  <div class="mt-2">
                    <p class="text-xs text-base-content/60">
                      <span class="font-medium">Notes:</span> {payment.notes}
                    </p>
                  </div>
                <% end %>

                <%!-- Attached Files --%>
                <%= if payment.files != [] && payment.files != nil do %>
                  <div class="mt-3 pt-3 border-t border-base-200">
                    <p class="text-xs font-medium text-base-content/60 mb-2 flex items-center gap-1">
                      <.icon name="hero-paper-clip" class="w-3.5 h-3.5" />
                      Attached Files ({length(payment.files)})
                    </p>
                    <div class="flex flex-wrap gap-2">
                      <%= for file <- payment.files do %>
                        <.file_chip file={file} />
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </:timeline_item>
            </.timeline_container>

            <%!-- Timeline Footer: Total Summary --%>
            <div class="pt-3 border-t border-base-300/50 px-4 sm:px-6">
              <div class="flex items-center justify-between text-sm">
                <span class="text-base-content/60">Total Paid</span>
                <span class="font-semibold text-success">
                  {format_currency(@item.total_paid)} / {format_currency(@item.rent)}
                </span>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp payment_count_indicator(assigns) do
    ~H"""
    <span class={[
      "px-2 py-0.5 rounded-full text-xs font-medium",
      @is_expanded && "bg-primary/10 text-primary",
      !@is_expanded && "bg-base-200 text-base-content/60"
    ]}>
      <%= if @variant == :desktop do %>
        {@payment_count} payment{if @payment_count > 1, do: "s"}
      <% else %>
        {@payment_count} pmt{if @payment_count > 1, do: "s"}.
      <% end %>
    </span>
    """
  end

  # Payment Submit Button Component (shared between mobile and desktop)
  defp payment_submit_button(assigns) do
    extra_class = Map.get(assigns, :class, "")

    assigns = assign(assigns, :extra_class, extra_class)

    ~H"""
    <.button
      phx-click="show_payment_modal"
      phx-value-contract-id={@contract_id}
      phx-value-month={@month}
      variant="primary"
      class={["btn-sm whitespace-nowrap", @extra_class]}
      phx-stop
    >
      <.icon name="hero-plus" class="w-4 h-4 mr-1" /> Pay
    </.button>
    """
  end

  # Contract Quick Access Component - Styled to match property_live/show.ex active contract section
  defp contract_quick_access(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 p-6">
      <%!-- Section Header with Status --%>
      <div class="flex items-center justify-between gap-4 pb-4 border-b border-base-200 mb-6">
        <div class="flex items-center gap-2">
          <div class="p-1.5 bg-success/10 rounded-lg flex items-center justify-center">
            <.icon name="hero-document-text" class="w-5 h-5 text-success" />
          </div>
          <h3 class="text-lg font-semibold text-base-content">Contract Details</h3>
        </div>
        <.contract_status_badge status={@contract_status} />
      </div>

      <%!-- Contract Details Grid --%>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <%!-- Lease Period --%>
        <div class="space-y-2">
          <label class="text-sm font-medium text-base-content/60">Lease Period</label>
          <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
            <.icon name="hero-calendar" class="w-5 h-5 text-base-content/50" />
            <span class="font-medium text-base-content text-sm">
              {format_date(@contract.start_date)} — {format_date(@contract.end_date)}
            </span>
          </div>
        </div>

        <%!-- Monthly Rent --%>
        <div class="space-y-2">
          <label class="text-sm font-medium text-base-content/60">Monthly Rent</label>
          <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
            <.icon name="hero-banknotes" class="w-5 h-5 text-base-content/50" />
            <span class="font-semibold text-base-content flex items-center gap-2">
              {format_currency(Contracts.latest_rent_value(@contract))}
              <%= if @contract.index_type do %>
                <span class="inline-flex items-center gap-1 px-2 py-0.5 bg-info/10 text-info rounded-full text-xs font-medium">
                  <.icon name="hero-arrow-trending-up" class="w-3 h-3" /> Indexed
                </span>
              <% end %>
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

        <%!-- Property Info --%>
        <div class="space-y-2">
          <label class="text-sm font-medium text-base-content/60">Property</label>
          <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
            <.icon name="hero-building-office" class="w-5 h-5 text-base-content/50" />
            <div class="min-w-0">
              <p class="font-medium text-base-content text-sm truncate">
                {@contract.property.name}
              </p>
              <p class="text-xs text-base-content/60 truncate">
                {@contract.property.address}
              </p>
            </div>
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

          <%!-- Days Left --%>
          <.days_left_field contract={@contract} />
        <% end %>
      </div>

      <%!-- Contract Progress Bar --%>
      <div class="mt-6 pt-6 border-t border-base-200">
        <.contract_progress_bar contract={@contract} compact show_status_badge={false} />
      </div>

      <%!-- Contract Notes --%>
      <%= if @contract.notes && @contract.notes != "" do %>
        <div class="mt-6 pt-6 border-t border-base-200">
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
        </div>
      <% end %>
    </div>
    """
  end

  # Days Left Field Component
  defp days_left_field(assigns) do
    days_remaining = Contracts.days_until_end(assigns.contract)

    assigns =
      assign(assigns, :days_remaining, days_remaining)

    ~H"""
    <div class="space-y-2">
      <label class="text-sm font-medium text-base-content/60">Days Left</label>
      <div class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg">
        <.icon name="hero-clock" class="w-5 h-5 text-base-content/50" />
        <div>
          <%= if @days_remaining do %>
            <p class="font-medium text-base-content">{@days_remaining} days</p>
          <% else %>
            <span class="font-medium text-base-content/50">-</span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # No Contract Message (existing)
  defp no_contract_message(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 p-12 text-center">
      <.icon name="hero-home" class="w-16 h-16 mx-auto text-base-content/30 mb-4" />
      <h2 class="text-xl font-semibold mb-2">No Active Lease</h2>
      <p class="text-base-content/60">You don't have an active rental contract.</p>
    </div>
    """
  end

  # Helper functions for tenant dashboard

  # Returns true if the payment item is for the current payment period
  defp current_payment_month?(item, contract) do
    current_payment_num = Contracts.get_current_payment_number(contract)
    item.payment_number == current_payment_num
  end

  # Returns visual styling information for a payment item based on its status and overdue state.
  # Highlights the current payment month with info colors.
  # Overdue status takes precedence over partial status.
  # Returns a map with :icon, :bg_color, and :text_color
  defp payment_item_visuals(item, contract) do
    cond do
      item.status == :paid ->
        %{icon: "hero-check", bg_color: "bg-success/10", text_color: "text-success"}

      current_payment_month?(item, contract) ->
        %{icon: "hero-calendar", bg_color: "bg-info/10", text_color: "text-info"}

      item.is_overdue ->
        %{icon: "hero-clock", bg_color: "bg-error/10", text_color: "text-error"}

      item.status == :partial ->
        %{icon: "hero-minus", bg_color: "bg-warning/10", text_color: "text-warning"}

      true ->
        %{icon: "hero-clock", bg_color: "bg-base-200", text_color: "text-base-content/50"}
    end
  end
end
