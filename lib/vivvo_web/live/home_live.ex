defmodule VivvoWeb.HomeLive do
  @moduledoc """
  Main dashboard LiveView for both owners and tenants.

  Owners see analytics, property metrics, and pending payment validations.
  Tenants see their contract details and payment history.
  """
  use VivvoWeb, :live_view

  alias Vivvo.Accounts.Scope
  alias Vivvo.Contracts
  alias Vivvo.Payments

  # Number of months to show in income trend chart
  @trend_months 6

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if Scope.tenant?(scope) do
      # Tenant state is handled by handle_params
      # Initialize with empty assigns, handle_params will populate
      {:ok,
       socket
       |> assign(:contracts, [])
       |> assign(:selected_contract, nil)
       |> assign(:current_expanded, true)
       |> assign(:history_expanded, false)
       |> assign(:submitting_payment, nil)
       |> assign(:payment_form, nil)
       |> assign(:payment_summary, %{
         rent: nil,
         accepted_total: nil,
         pending_total: nil,
         remaining: nil
       })}
    else
      # Owner view - new dashboard with streams for large collections
      socket =
        socket
        |> assign(:today, Date.utc_today())
        |> assign(:rejecting_payment, nil)
        |> refresh_dashboard_data(scope)

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    scope = socket.assigns.current_scope

    if Scope.tenant?(scope) do
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

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("accept_payment", %{"id" => payment_id}, socket) do
    scope = socket.assigns.current_scope

    if Scope.owner?(scope) do
      do_accept_payment(socket, scope, payment_id)
    else
      {:noreply, put_flash(socket, :error, "Unauthorized action")}
    end
  end

  @impl true
  def handle_event("reject_payment", %{"rejection-reason" => reason}, socket) do
    scope = socket.assigns.current_scope
    payment = socket.assigns.rejecting_payment

    if Scope.owner?(scope) && payment do
      do_reject_payment(socket, scope, payment.id, reason)
    else
      {:noreply, put_flash(socket, :error, "Unauthorized action")}
    end
  end

  @impl true
  def handle_event("select_contract", %{"id" => contract_id}, socket) do
    # Verify the contract belongs to this tenant
    if Enum.any?(socket.assigns.contracts, &(to_string(&1.id) == contract_id)) do
      {:noreply, push_patch(socket, to: ~p"/?property=#{contract_id}")}
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
  def handle_event("scroll_to_payments", _params, socket) do
    {:noreply, push_event(socket, "scroll_to", %{id: "current-payments"})}
  end

  @impl true
  def handle_event("scroll_to_upcoming", _params, socket) do
    {:noreply, push_event(socket, "scroll_to", %{id: "upcoming-payments"})}
  end

  @impl true
  def handle_event("show_reject_modal", %{"payment-id" => payment_id}, socket) do
    scope = socket.assigns.current_scope

    case Payments.get_payment(scope, payment_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Payment not found")}

      payment ->
        {:noreply, assign(socket, :rejecting_payment, payment)}
    end
  end

  @impl true
  def handle_event("close_reject_modal", _params, socket) do
    {:noreply, assign(socket, :rejecting_payment, nil)}
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

      # Calculate payment totals for display and validation
      accepted_total = Payments.total_accepted_for_month(scope, contract.id, month_num)
      pending_total = Payments.total_pending_for_month(scope, contract.id, month_num)
      remaining = Decimal.sub(contract.rent, Decimal.add(accepted_total, pending_total))

      # Pre-populate with minimum of rent or remaining allowance
      initial_amount = Decimal.min(contract.rent, remaining)
      initial_attrs = %{"amount" => initial_amount}

      changeset =
        Payments.change_payment(
          scope,
          %Vivvo.Payments.Payment{},
          initial_attrs,
          remaining_allowance: remaining
        )

      {:noreply,
       socket
       |> assign(:submitting_payment, {contract, month_num})
       |> assign(:payment_form, to_form(changeset))
       |> assign(:payment_summary, %{
         rent: contract.rent,
         accepted_total: accepted_total,
         pending_total: pending_total,
         remaining: remaining
       })}
    else
      {:noreply, put_flash(socket, :error, "Contract not found")}
    end
  end

  @impl true
  def handle_event("close_payment_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:submitting_payment, nil)
     |> assign(:payment_form, nil)
     |> assign(:payment_summary, nil)}
  end

  @impl true
  def handle_event("validate_payment", %{"payment" => params}, socket) do
    scope = socket.assigns.current_scope
    {contract, month} = socket.assigns.submitting_payment

    # Get payment totals for display (updated in real-time)
    accepted_total = Payments.total_accepted_for_month(scope, contract.id, month)
    pending_total = Payments.total_pending_for_month(scope, contract.id, month)
    remaining = Decimal.sub(contract.rent, Decimal.add(accepted_total, pending_total))

    changeset =
      Payments.change_payment(
        scope,
        %Vivvo.Payments.Payment{},
        params,
        remaining_allowance: remaining
      )
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(payment_form: to_form(changeset))
     |> assign(:payment_summary, %{
       rent: contract.rent,
       accepted_total: accepted_total,
       pending_total: pending_total,
       remaining: remaining
     })}
  end

  @impl true
  def handle_event("submit_payment", %{"payment" => params}, socket) do
    scope = socket.assigns.current_scope
    {contract, month} = socket.assigns.submitting_payment

    # Re-calculate totals before submission to prevent race conditions
    accepted_total = Payments.total_accepted_for_month(scope, contract.id, month)
    pending_total = Payments.total_pending_for_month(scope, contract.id, month)
    remaining_allowance = Decimal.sub(contract.rent, Decimal.add(accepted_total, pending_total))

    attrs =
      params
      |> Map.put("contract_id", contract.id)
      |> Map.put("payment_number", month)

    case Payments.create_payment(scope, attrs, remaining_allowance: remaining_allowance) do
      {:ok, _payment} ->
        contracts = Contracts.list_contracts_for_tenant(scope)

        selected_contract =
          Enum.find(contracts, &(to_string(&1.id) == to_string(contract.id))) ||
            List.first(contracts)

        {:noreply,
         socket
         |> assign(:submitting_payment, nil)
         |> assign(:payment_form, nil)
         |> assign(:payment_summary, nil)
         |> assign(:contracts, contracts)
         |> assign(:selected_contract, selected_contract)
         |> put_flash(:info, "Payment submitted successfully!")}

      {:error, changeset} ->
        {:noreply, assign(socket, payment_form: to_form(changeset))}
    end
  end

  defp do_accept_payment(socket, scope, payment_id) do
    case Payments.get_payment(scope, payment_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Payment not found")}

      payment ->
        handle_accept_payment_result(socket, scope, Payments.accept_payment(scope, payment))
    end
  end

  defp handle_accept_payment_result(socket, scope, {:ok, _payment}) do
    socket =
      socket
      |> refresh_dashboard_data(scope)
      |> put_flash(:info, "Payment accepted successfully")

    {:noreply, socket}
  end

  defp handle_accept_payment_result(socket, _scope, {:error, _changeset}) do
    {:noreply, put_flash(socket, :error, "Failed to accept payment")}
  end

  defp do_reject_payment(socket, scope, payment_id, reason) do
    case Payments.get_payment(scope, payment_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Payment not found")}

      payment ->
        handle_reject_payment_result(
          socket,
          scope,
          Payments.reject_payment(scope, payment, reason)
        )
    end
  end

  defp handle_reject_payment_result(socket, scope, {:ok, payment}) do
    pending_payments = Payments.pending_payments_for_validation(scope)

    socket =
      socket
      |> stream_delete(:pending_payments, payment)
      |> assign(:rejecting_payment, nil)
      |> assign(:pending_payments_empty?, pending_payments == [])
      |> put_flash(:info, "Payment rejected")

    {:noreply, socket}
  end

  defp handle_reject_payment_result(socket, _scope, {:error, _changeset}) do
    {:noreply, put_flash(socket, :error, "Failed to reject payment")}
  end

  defp refresh_dashboard_data(socket, scope) do
    today = Date.utc_today()
    pending_payments = Payments.pending_payments_for_validation(scope)

    socket
    |> assign(:expected_income, Payments.expected_income_for_month(scope, today))
    |> assign(:received_income, Payments.received_income_for_month(scope, today))
    |> assign(:outstanding_balance, Payments.outstanding_balance_for_month(scope, today))
    |> assign(:collection_rate, Payments.collection_rate_for_month(scope, today))
    |> assign(:income_trend, Payments.income_trend(scope, @trend_months))
    |> assign(:outstanding_aging, Payments.outstanding_aging(scope))
    |> assign(:total_outstanding, Payments.total_outstanding(scope))
    |> assign(:pending_payments_empty?, pending_payments == [])
    |> stream(:pending_payments, pending_payments, reset: true)
    |> assign(:property_metrics, Contracts.property_performance_metrics(scope))
    |> assign(:dashboard_summary, Contracts.dashboard_summary(scope))
    |> assign(:payment_counts, Payments.payment_counts_by_status(scope))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%= if Scope.tenant?(@current_scope) do %>
        <.tenant_dashboard
          contracts={@contracts}
          current_scope={@current_scope}
          selected_contract={@selected_contract}
          current_expanded={@current_expanded}
          history_expanded={@history_expanded}
          submitting_payment={@submitting_payment}
          payment_form={@payment_form}
          payment_summary={@payment_summary}
        />
      <% else %>
        <.owner_dashboard
          today={@today}
          expected_income={@expected_income}
          received_income={@received_income}
          outstanding_balance={@outstanding_balance}
          collection_rate={@collection_rate}
          income_trend={@income_trend}
          outstanding_aging={@outstanding_aging}
          total_outstanding={@total_outstanding}
          pending_payments_empty?={@pending_payments_empty?}
          property_metrics={@property_metrics}
          dashboard_summary={@dashboard_summary}
          payment_counts={@payment_counts}
          streams={@streams}
          rejecting_payment={@rejecting_payment}
        />
      <% end %>
    </Layouts.app>
    """
  end

  # Owner Dashboard Component
  defp owner_dashboard(assigns) do
    ~H"""
    <div class="space-y-6 sm:space-y-8">
      <%!-- Page Header --%>
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 class="text-2xl sm:text-3xl font-bold tracking-tight text-base-content">
            Dashboard
          </h1>
          <p class="mt-1 text-sm text-base-content/70">
            Welcome back! Here's what's happening with your properties.
          </p>
        </div>
        <div class="flex items-center gap-2">
          <span class="text-sm text-base-content/60">
            {@today |> Calendar.strftime("%B %d, %Y")}
          </span>
        </div>
      </div>

      <%!-- Summary Stats Row --%>
      <.summary_stats summary={@dashboard_summary} payment_counts={@payment_counts} />

      <%!-- Executive Summary Section (Top) --%>
      <.executive_summary
        expected_income={@expected_income}
        received_income={@received_income}
        outstanding_balance={@outstanding_balance}
        collection_rate={@collection_rate}
      />

      <%!-- Trends & Health Section (Middle) --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <.income_trend_card income_trend={@income_trend} />
        <.outstanding_aging_card
          outstanding_aging={@outstanding_aging}
          total_outstanding={@total_outstanding}
        />
      </div>

      <%!-- Property Performance Section --%>
      <.property_performance_table property_metrics={@property_metrics} />

      <%!-- Payment Validation Queue (Bottom) --%>
      <.payment_validation_queue
        pending_payments_empty?={@pending_payments_empty?}
        streams={@streams}
      />

      <%!-- Reject Payment Modal --%>
      <%= if @rejecting_payment do %>
        <.reject_modal
          id="reject-payment-modal"
          title="Reject Payment"
          description="Please provide a reason for rejecting this payment."
          submit_event="reject_payment"
          close_event="close_reject_modal"
          reason_label="Rejection Reason"
          reason_placeholder="Enter rejection reason..."
          submit_text="Reject Payment"
        />
      <% end %>
    </div>
    """
  end

  # Summary Stats Component
  defp summary_stats(assigns) do
    ~H"""
    <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
      <div class="bg-base-100 rounded-xl p-4 shadow-sm border border-base-200">
        <div class="flex items-center gap-3">
          <div class="p-2 bg-primary/10 rounded-lg">
            <.icon name="hero-building-office" class="w-5 h-5 text-primary" />
          </div>
          <div>
            <p class="text-sm text-base-content/60">Properties</p>
            <p class="text-2xl font-bold">{@summary.total_properties}</p>
          </div>
        </div>
      </div>

      <div class="bg-base-100 rounded-xl p-4 shadow-sm border border-base-200">
        <div class="flex items-center gap-3">
          <div class="p-2 bg-success/10 rounded-lg">
            <.icon name="hero-document-text" class="w-5 h-5 text-success" />
          </div>
          <div>
            <p class="text-sm text-base-content/60">Contracts</p>
            <p class="text-2xl font-bold">{@summary.total_contracts}</p>
          </div>
        </div>
      </div>

      <div class="bg-base-100 rounded-xl p-4 shadow-sm border border-base-200">
        <div class="flex items-center gap-3">
          <div class="p-2 bg-info/10 rounded-lg">
            <.icon name="hero-users" class="w-5 h-5 text-info" />
          </div>
          <div>
            <p class="text-sm text-base-content/60">Tenants</p>
            <p class="text-2xl font-bold">{@summary.total_tenants}</p>
          </div>
        </div>
      </div>

      <div class="bg-base-100 rounded-xl p-4 shadow-sm border border-base-200">
        <div class="flex items-center gap-3">
          <div class="p-2 bg-warning/10 rounded-lg">
            <.icon name="hero-clock" class="w-5 h-5 text-warning" />
          </div>
          <div>
            <p class="text-sm text-base-content/60">Pending</p>
            <p class="text-2xl font-bold">{@payment_counts.pending}</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Executive Summary Component
  defp executive_summary(assigns) do
    percentage = Float.round(assigns.collection_rate, 1)

    assigns = assign(assigns, :percentage, percentage)

    ~H"""
    <div class="bg-base-100 rounded-2xl p-6 shadow-sm border border-base-200">
      <div class="flex items-center gap-2 mb-6">
        <.icon name="hero-chart-pie" class="w-5 h-5 text-primary" />
        <h2 class="text-lg font-semibold">This Month's Overview</h2>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <%!-- Expected Income --%>
        <div class="space-y-2">
          <p class="text-sm text-base-content/60">Expected Income</p>
          <p class="text-3xl sm:text-4xl font-bold text-base-content">
            {format_currency(@expected_income)}
          </p>
          <p class="text-sm text-base-content/50">Total rent due this month</p>
        </div>

        <%!-- Collection Progress --%>
        <div class="space-y-2">
          <p class="text-sm text-base-content/60">Collection Progress</p>
          <div class="flex items-baseline gap-2">
            <p class="text-3xl sm:text-4xl font-bold text-success">{@percentage}%</p>
            <span class="text-sm text-base-content/50">collected</span>
          </div>
          <div class="w-full bg-base-200 rounded-full h-2.5">
            <div
              class="bg-success h-2.5 rounded-full transition-all duration-500"
              style={"width: #{min(@percentage, 100)}%"}
            >
            </div>
          </div>
        </div>

        <%!-- Outstanding Balance --%>
        <div class="space-y-2">
          <p class="text-sm text-base-content/60">Outstanding</p>
          <p class={[
            "text-3xl sm:text-4xl font-bold",
            Decimal.gt?(@outstanding_balance, Decimal.new(0)) && "text-error",
            Decimal.eq?(@outstanding_balance, Decimal.new(0)) && "text-success"
          ]}>
            {format_currency(@outstanding_balance)}
          </p>
          <p class="text-sm text-base-content/50">
            <%= cond do %>
              <% Decimal.gt?(@outstanding_balance, Decimal.new(0)) -> %>
                Still to collect
              <% Decimal.lt?(@outstanding_balance, Decimal.new(0)) -> %>
                Overpaid amount
              <% true -> %>
                All caught up!
            <% end %>
          </p>
        </div>
      </div>

      <div class="mt-6 pt-6 border-t border-base-200 flex flex-wrap items-center gap-4 text-sm">
        <div class="flex items-center gap-2">
          <div class="w-3 h-3 rounded-full bg-success"></div>
          <span class="text-base-content/70">Received: {format_currency(@received_income)}</span>
        </div>
        <%= if Decimal.gt?(@outstanding_balance, Decimal.new(0)) do %>
          <div class="flex items-center gap-2">
            <div class="w-3 h-3 rounded-full bg-error"></div>
            <span class="text-base-content/70">Missing: {format_currency(@outstanding_balance)}</span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Income Trend Card Component
  defp income_trend_card(assigns) do
    max_expected =
      assigns.income_trend
      |> Enum.map(&elem(&1, 1))
      |> Enum.max_by(&Decimal.to_float/1, fn -> Decimal.new(0) end)
      |> Decimal.to_float()

    max_expected = max(max_expected, 1.0)

    # Pre-compute all trend bar data
    trend_bars =
      Enum.map(assigns.income_trend, fn {month_date, expected, received} ->
        calculate_trend_bar_data(month_date, expected, received, max_expected)
      end)

    assigns =
      assign(assigns,
        max_expected: max_expected,
        trend_bars: trend_bars
      )

    ~H"""
    <div class="bg-base-100 rounded-2xl p-6 shadow-sm border border-base-200">
      <div class="flex items-center gap-2 mb-6">
        <.icon name="hero-chart-bar" class="w-5 h-5 text-primary" />
        <h2 class="text-lg font-semibold">Income Trend</h2>
      </div>

      <div class="space-y-4">
        <%= for bar <- @trend_bars do %>
          <div class="space-y-2">
            <div class="flex justify-between text-sm">
              <span class="text-base-content/70">{bar.month_label}</span>
              <span class="font-medium">
                {format_currency(bar.received)} / {format_currency(bar.expected)}
              </span>
            </div>
            <div class="relative h-8 bg-base-200 rounded-lg overflow-hidden">
              <%!-- Expected amount bar (background) --%>
              <div
                class="absolute top-0 left-0 h-full bg-base-300/50 rounded-l-lg"
                style={"width: #{bar.expected_pct}%"}
              >
              </div>
              <%!-- Received amount bar --%>
              <div
                class={[
                  "absolute top-0 left-0 h-full rounded-l-lg transition-all duration-500",
                  bar.received_pct >= 100 && "bg-success",
                  bar.received_pct >= 50 && bar.received_pct < 100 && "bg-warning",
                  bar.received_pct < 50 && "bg-error"
                ]}
                style={"width: #{bar.received_pct}%"}
              >
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <div class="mt-4 pt-4 border-t border-base-200 flex items-center justify-center gap-4 text-xs">
        <div class="flex items-center gap-1.5">
          <div class="w-3 h-3 rounded bg-success"></div>
          <span class="text-base-content/60">{"100% Collected"}</span>
        </div>
        <div class="flex items-center gap-1.5">
          <div class="w-3 h-3 rounded bg-warning"></div>
          <span class="text-base-content/60">{">= 50% Collected"}</span>
        </div>
        <div class="flex items-center gap-1.5">
          <div class="w-3 h-3 rounded bg-error"></div>
          <span class="text-base-content/60">{"< 50% Collected"}</span>
        </div>
        <div class="flex items-center gap-1.5">
          <div class="w-3 h-3 rounded bg-base-300/50"></div>
          <span class="text-base-content/60">{"Expected"}</span>
        </div>
      </div>
    </div>
    """
  end

  # Outstanding Aging Card Component
  defp outstanding_aging_card(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl p-6 shadow-sm border border-base-200">
      <div class="flex items-center justify-between mb-6">
        <div class="flex items-center gap-2">
          <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-warning" />
          <h2 class="text-lg font-semibold">Outstanding Balances</h2>
        </div>
        <span class="text-2xl font-bold">{format_currency(@total_outstanding)}</span>
      </div>

      <div class="space-y-4">
        <%!-- Current --%>
        <.aging_row
          label="Current"
          amount={@outstanding_aging.current}
          color="bg-info"
          description="Not yet due"
        />

        <%!-- 0-7 Days --%>
        <.aging_row
          label="0-7 days"
          amount={@outstanding_aging.days_0_7}
          color="bg-warning"
          description="Recently overdue"
        />

        <%!-- 8-30 Days --%>
        <.aging_row
          label="8-30 days"
          amount={@outstanding_aging.days_8_30}
          color="bg-warning/70"
          description="Overdue"
        />

        <%!-- 31+ Days --%>
        <.aging_row
          label="31+ days"
          amount={@outstanding_aging.days_31_plus}
          color="bg-error"
          description="Seriously overdue"
        />
      </div>

      <%= if Decimal.gt?(@total_outstanding, Decimal.new(0)) do %>
        <div class="mt-4 p-3 bg-warning/10 rounded-lg border border-warning/20">
          <div class="flex items-start gap-2">
            <.icon name="hero-light-bulb" class="w-5 h-5 text-warning flex-shrink-0 mt-0.5" />
            <p class="text-sm text-base-content/80">
              Consider following up on
              <%= if Decimal.gt?(@outstanding_aging.days_31_plus, Decimal.new(0)) do %>
                seriously overdue payments
              <% else %>
                outstanding payments
              <% end %>
              to improve your collection rate.
            </p>
          </div>
        </div>
      <% else %>
        <div class="mt-4 p-3 bg-success/10 rounded-lg border border-success/20">
          <div class="flex items-start gap-2">
            <.icon name="hero-check-circle" class="w-5 h-5 text-success flex-shrink-0 mt-0.5" />
            <p class="text-sm text-base-content/80">
              Great job! All payments are up to date.
            </p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp aging_row(assigns) do
    ~H"""
    <div class="flex items-center gap-4">
      <div class={["w-2 h-12 rounded-full", @color]}></div>
      <div class="flex-1">
        <div class="flex justify-between items-center">
          <span class="font-medium text-base-content">{@label}</span>
          <span class="font-bold">{format_currency(@amount)}</span>
        </div>
        <p class="text-sm text-base-content/50">{@description}</p>
      </div>
    </div>
    """
  end

  # Property Performance Table Component
  defp property_performance_table(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 overflow-hidden">
      <div class="p-6 border-b border-base-200">
        <div class="flex items-center gap-2">
          <.icon name="hero-building-office-2" class="w-5 h-5 text-primary" />
          <h2 class="text-lg font-semibold">Property Performance</h2>
        </div>
      </div>

      <%= if @property_metrics != [] do %>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="bg-base-200/50">
              <tr>
                <th class="px-4 py-3 text-left font-medium text-base-content/70">Property</th>
                <th class="px-4 py-3 text-center font-medium text-base-content/70">State</th>
                <th class="px-4 py-3 text-right font-medium text-base-content/70">Income</th>
                <th class="px-4 py-3 text-right font-medium text-base-content/70">Expected</th>
                <th class="px-4 py-3 text-center font-medium text-base-content/70">Collection</th>
                <th class="px-4 py-3 text-center font-medium text-base-content/70">Avg Delay</th>
                <th class="px-4 py-3 text-center font-medium text-base-content/70">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-200">
              <%= for metric <- @property_metrics do %>
                <tr class="hover:bg-base-200/30 transition-colors">
                  <td class="px-4 py-3 min-w-[180px]">
                    <div class="font-medium whitespace-nowrap">{metric.property.name}</div>
                    <div class="text-xs text-base-content/50 truncate max-w-[200px]">
                      {metric.property.address}
                    </div>
                  </td>
                  <td class="px-4 py-3 text-center">
                    <%= if metric.state == :occupied do %>
                      <div class="inline-flex items-center gap-1.5 px-2 py-1 bg-success/10 text-success rounded-full text-xs font-medium">
                        Occupied
                      </div>
                    <% else %>
                      <div class="inline-flex items-center gap-1.5 px-2 py-1 bg-base-300/30 text-base-content/60 rounded-full text-xs font-medium">
                        Vacant
                      </div>
                    <% end %>
                  </td>
                  <td class="px-4 py-3 text-right font-medium">
                    <%= if metric.state == :occupied do %>
                      {format_currency(metric.total_income)}
                    <% end %>
                  </td>
                  <td class="px-4 py-3 text-right text-base-content/70">
                    <%= if metric.state == :occupied do %>
                      {format_currency(metric.total_expected)}
                    <% end %>
                  </td>
                  <td class="px-4 py-3">
                    <%= if metric.state == :occupied do %>
                      <div class="flex items-center justify-center gap-2">
                        <div class="w-16 bg-base-200 rounded-full h-1.5">
                          <div
                            class={[
                              "h-1.5 rounded-full",
                              metric.collection_rate >= 90 && "bg-success",
                              metric.collection_rate >= 70 && metric.collection_rate < 90 &&
                                "bg-warning",
                              metric.collection_rate < 70 && "bg-error"
                            ]}
                            style={"width: #{min(metric.collection_rate, 100)}%"}
                          >
                          </div>
                        </div>
                        <span class="text-xs font-medium w-10 text-right">
                          {Float.round(metric.collection_rate, 0)}%
                        </span>
                      </div>
                    <% end %>
                  </td>
                  <td class="px-4 py-3 text-center">
                    <%= if metric.state == :occupied do %>
                      <%= if metric.avg_delay_days > 0 do %>
                        <span class="text-error">{metric.avg_delay_days}d</span>
                      <% else %>
                        <span class="text-success">On time</span>
                      <% end %>
                    <% end %>
                  </td>
                  <td class="px-4 py-3 text-center">
                    <%= if metric.state == :occupied do %>
                      <.property_status_badge collection_rate={metric.collection_rate} />
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% else %>
        <div class="p-8 text-center">
          <.icon name="hero-building-office" class="w-12 h-12 mx-auto text-base-content/30 mb-3" />
          <p class="text-base-content/60">No active properties found</p>
          <.link href={~p"/properties/new"} class="btn btn-primary btn-sm mt-4">
            <.icon name="hero-plus" class="w-4 h-4 mr-1" /> Add Property
          </.link>
        </div>
      <% end %>
    </div>
    """
  end

  # Payment Validation Queue Component
  defp payment_validation_queue(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 overflow-hidden">
      <div class="p-4 sm:p-6 border-b border-base-200">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <.icon name="hero-clipboard-document-check" class="w-5 h-5 text-primary" />
            <h2 class="text-base sm:text-lg font-semibold">Payment Validation Queue</h2>
          </div>
          <%= if not @pending_payments_empty? do %>
            <span class="px-2.5 py-1 bg-warning/10 text-warning rounded-full text-xs sm:text-sm font-medium">
              pending
            </span>
          <% end %>
        </div>
      </div>

      <%= if @pending_payments_empty? do %>
        <div class="p-8 text-center">
          <.icon name="hero-check-circle" class="w-12 h-12 mx-auto text-success mb-3" />
          <p class="text-base-content/60">No pending payments to validate</p>
          <p class="text-sm text-base-content/50 mt-1">
            All caught up! New payments will appear here.
          </p>
        </div>
      <% else %>
        <%!-- Desktop Header Row --%>
        <div class="hidden sm:grid sm:grid-cols-8 sm:gap-4 px-5 py-3 bg-base-200/50 border-b border-base-200 text-xs font-medium text-base-content/60 items-center">
          <span class="col-span-2">Tenant</span>
          <span class="col-span-1">Period</span>
          <span class="col-span-2">Amount Received</span>
          <span class="col-span-1">Amount Expected</span>
          <span class="col-span-2 text-right">Actions</span>
        </div>
        <div id="pending-payments" phx-update="stream" class="divide-y divide-base-200">
          <div :for={{dom_id, payment} <- @streams.pending_payments} id={dom_id}>
            <.pending_payment_row payment={payment} />
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp pending_payment_row(assigns) do
    contract = assigns.payment.contract
    tenant = contract.tenant
    property = contract.property

    expected_amount = contract.rent
    paid_amount = assigns.payment.amount

    payment_status =
      cond do
        Decimal.eq?(paid_amount, expected_amount) -> :correct
        Decimal.gt?(paid_amount, expected_amount) -> :overpaid
        true -> :underpaid
      end

    assigns =
      assign(assigns,
        tenant: tenant,
        property: property,
        expected_amount: expected_amount,
        payment_status: payment_status
      )

    ~H"""
    <div class="px-4 py-4 sm:px-5 sm:py-0 hover:bg-base-200/30 transition-colors">
      <%!-- Mobile Layout (stacked) --%>
      <div class="flex flex-col sm:hidden gap-3 py-0 sm:py-4">
        <%!-- Mobile: Tenant & Property --%>
        <div class="flex items-start justify-between gap-2">
          <div class="min-w-0 flex-1">
            <p class="font-medium text-sm truncate">
              {@tenant.first_name} {@tenant.last_name}
            </p>
            <p class="text-xs text-base-content/60 truncate">
              {@property.name}
            </p>
          </div>
          <div class="text-right">
            <p class={[
              "text-base font-bold",
              @payment_status == :correct && "text-success",
              @payment_status == :underpaid && "text-warning",
              @payment_status == :overpaid && "text-info"
            ]}>
              {format_currency(@payment.amount)}
            </p>
          </div>
        </div>

        <%!-- Mobile: Period & Status --%>
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3 text-xs text-base-content/70">
            <span class="inline-flex items-center gap-1">
              <.icon name="hero-calendar" class="w-3.5 h-3.5" /> Period {@payment.payment_number}
            </span>
            <span>{@payment.inserted_at |> Calendar.strftime("%b %d")}</span>
          </div>
          <%= case @payment_status do %>
            <% :correct -> %>
              <span class="text-xs text-success font-medium">Matches</span>
            <% :underpaid -> %>
              <span class="text-xs text-warning font-medium">
                -{format_currency(Decimal.sub(@expected_amount, @payment.amount))}
              </span>
            <% :overpaid -> %>
              <span class="text-xs text-info font-medium">
                +{format_currency(Decimal.sub(@payment.amount, @expected_amount))}
              </span>
          <% end %>
        </div>

        <%!-- Mobile: Actions --%>
        <div class="flex items-center gap-2 mt-1">
          <button
            phx-click="accept_payment"
            phx-value-id={@payment.id}
            class="btn btn-success btn-sm flex-1"
          >
            <.icon name="hero-check" class="w-4 h-4" />
          </button>
          <button
            phx-click="show_reject_modal"
            phx-value-payment-id={@payment.id}
            class="btn btn-error btn-outline btn-sm flex-1"
          >
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
        </div>
      </div>

      <%!-- Desktop/Tablet Layout (grid-based) --%>
      <div class="hidden sm:grid sm:grid-cols-8 sm:items-center sm:gap-4 sm:py-4">
        <%!-- Tenant Column with Avatar --%>
        <div class="col-span-2 flex items-center gap-3 min-w-0">
          <div class="w-9 h-9 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
            <span class="text-xs font-bold text-primary">
              {String.first(@tenant.first_name)}{String.first(@tenant.last_name)}
            </span>
          </div>
          <div class="min-w-0">
            <p class="font-medium text-sm truncate">
              {@tenant.first_name} {@tenant.last_name}
            </p>
            <p class="text-xs text-base-content/60 truncate">
              {@property.name}
            </p>
          </div>
        </div>

        <%!-- Period Column (moved from under tenant) --%>
        <div class="col-span-1 text-sm">
          <p class="font-medium">Period {@payment.payment_number}</p>
          <p class="text-xs text-base-content/60">
            {@payment.inserted_at |> Calendar.strftime("%b %d, %Y")}
          </p>
        </div>

        <%!-- Amount Column --%>
        <div class="col-span-2">
          <p class={[
            "text-base font-bold",
            @payment_status == :correct && "text-success",
            @payment_status == :underpaid && "text-warning",
            @payment_status == :overpaid && "text-info"
          ]}>
            {format_currency(@payment.amount)}
          </p>
          <p class="text-xs text-base-content/60">
            <%= case @payment_status do %>
              <% :correct -> %>
                <span class="text-success">Matches expected</span>
              <% :underpaid -> %>
                <span class="text-warning">
                  Under by {format_currency(Decimal.sub(@expected_amount, @payment.amount))}
                </span>
              <% :overpaid -> %>
                <span class="text-info">
                  Over by {format_currency(Decimal.sub(@payment.amount, @expected_amount))}
                </span>
            <% end %>
          </p>
        </div>

        <%!-- Expected Amount Column --%>
        <div class="col-span-1 text-sm">
          <p class="font-medium">{format_currency(@expected_amount)}</p>
          <p class="text-xs text-base-content/60">Expected</p>
        </div>

        <%!-- Actions Column --%>
        <div class="col-span-2 flex items-center gap-2 justify-end">
          <button
            phx-click="accept_payment"
            phx-value-id={@payment.id}
            class="btn btn-success btn-sm"
          >
            <.icon name="hero-check" class="w-4 h-4 mr-1" /> Accept
          </button>
          <button
            phx-click="show_reject_modal"
            phx-value-payment-id={@payment.id}
            class="btn btn-error btn-outline btn-sm"
          >
            <.icon name="hero-x-mark" class="w-4 h-4 mr-1" /> Reject
          </button>
        </div>
      </div>

      <%!-- Notes (shown on all screen sizes when present) --%>
      <%= if @payment.notes && @payment.notes != "" do %>
        <div class="mt-3 p-2.5 sm:p-3 bg-base-200/50 rounded-lg">
          <p class="text-xs sm:text-sm text-base-content/70">
            <span class="font-medium">Note:</span> {@payment.notes}
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  # Tenant Dashboard Component (redesigned per issue #14)
  defp tenant_dashboard(assigns) do
    ~H"""
    <div class="space-y-6 sm:space-y-8">
      <%= if @contracts != [] do %>
        <%!-- Property Switcher for Multiple Contracts --%>
        <%= if length(@contracts) > 1 do %>
          <.property_switcher contracts={@contracts} selected_contract={@selected_contract} />
        <% end %>

        <% contract = @selected_contract || List.first(@contracts)
        contract_status = Contracts.contract_status(contract)
        payment_status = Contracts.contract_payment_status(@current_scope, contract)
        total_due = Contracts.total_amount_due(@current_scope, contract)
        earliest_due = Contracts.earliest_due_date(@current_scope, contract)
        payment_statuses = Contracts.get_payment_statuses(@current_scope, contract)
        upcoming_payments = Contracts.get_upcoming_payments(contract)
        next_payment = List.first(upcoming_payments) %>

        <%!-- A. Header: Current Situation Snapshot --%>
        <.situation_snapshot
          contract={contract}
          contract_status={contract_status}
          payment_status={payment_status}
          total_due={total_due}
          earliest_due={earliest_due}
          next_payment={next_payment}
        />

        <%!-- B. Primary Action Zone --%>
        <.primary_action_zone
          contract={contract}
          payment_status={payment_status}
          total_due={total_due}
          scope={@current_scope}
        />

        <%!-- C. Payments Overview --%>
        <.payments_overview
          contract={contract}
          payment_statuses={payment_statuses}
          upcoming_payments={upcoming_payments}
          scope={@current_scope}
          current_expanded={@current_expanded}
          history_expanded={@history_expanded}
        />

        <%!-- D. Contract & Property Quick Access --%>
        <.contract_quick_access contract={contract} contract_status={contract_status} />

        <%!-- Submit Payment Modal --%>
        <%= if @submitting_payment && @payment_summary do %>
          <% {contract, month} = @submitting_payment %>
          <.submit_payment_modal
            id="submit-payment-modal"
            contract={contract}
            month={month}
            form={@payment_form}
            submit_event="submit_payment"
            close_event="close_payment_modal"
            rent={@payment_summary.rent}
            accepted_total={@payment_summary.accepted_total}
            pending_total={@payment_summary.pending_total}
            remaining={@payment_summary.remaining}
          />
        <% end %>
      <% else %>
        <.no_contract_message />
      <% end %>
    </div>
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
      <div class="flex -mx-4 px-4 overflow-x-auto scrollbar-hide gap-3 pb-1">
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
      if assigns.next_payment do
        Date.diff(assigns.next_payment.due_date, Date.utc_today())
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

        <%!-- Progress Bar for Payment --%>
        <%= if Decimal.gt?(@total_due, Decimal.new(0)) do %>
          <div class="mt-6 pt-6 border-t border-base-200">
            <div class="flex items-center justify-between text-sm mb-2">
              <span class="text-base-content/60">Payment Progress</span>
              <span class="font-medium text-error">Outstanding: {format_currency(@total_due)}</span>
            </div>
            <div class="w-full bg-base-200 rounded-full h-2.5">
              <div class="bg-error h-2.5 rounded-full" style="width: 0%"></div>
            </div>
            <p class="text-xs text-base-content/50 mt-2">
              Submit payment to bring your account up to date
            </p>
          </div>
        <% else %>
          <div class="mt-6 pt-6 border-t border-base-200">
            <div class="flex flex-col sm:flex-row sm:items-center gap-3">
              <%!-- Success Message --%>
              <div class="flex items-center gap-2 text-success">
                <.icon name="hero-check-circle" class="w-5 h-5" />
                <span class="font-medium">All payments are up to date!</span>
              </div>

              <%= if @next_payment do %>
                <%!-- Compact Next Payment Info --%>
                <div
                  id="upcoming-payments"
                  class="flex items-center gap-2 text-sm text-base-content/70 sm:ml-4"
                >
                  <.icon name="hero-calendar" class="w-4 h-4" />
                  <span>Next due {format_date(@next_payment.due_date)}</span>
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

  # Primary Action Zone Component
  defp primary_action_zone(assigns) do
    cta_info =
      cond do
        # Check if any payment is pending validation
        has_pending_payment?(assigns.contract.payments) ->
          {:view_pending, "View Pending Payment", "hero-eye", nil, nil}

        # Check if payment is due
        Decimal.gt?(assigns.total_due, Decimal.new(0)) ->
          month = get_earliest_unpaid_month(assigns.scope, assigns.contract)
          {:submit_payment, "Submit Payment", "hero-credit-card", assigns.contract.id, month}

        # All caught up - don't render the action zone
        true ->
          nil
      end

    # Don't render anything if tenant is all caught up
    if cta_info == nil do
      ~H"""
      """
    else
      {cta_type, cta_text, cta_icon, contract_id, month} = cta_info

      assigns =
        assign(assigns,
          cta_type: cta_type,
          cta_text: cta_text,
          cta_icon: cta_icon,
          contract_id: contract_id,
          month: month
        )

      ~H"""
      <div class="bg-gradient-to-r from-primary/5 to-primary/10 rounded-2xl p-6 border border-primary/20">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h2 class="text-lg font-semibold text-base-content">What do you need to do?</h2>
            <p class="text-sm text-base-content/70 mt-1">
              <%= case @cta_type do %>
                <% :submit_payment -> %>
                  You have an outstanding payment. Submit it now to avoid late fees.
                <% :view_pending -> %>
                  Your payment is being reviewed. You'll be notified when it's processed.
              <% end %>
            </p>
          </div>

          <%= if @cta_type == :submit_payment do %>
            <button
              phx-click="show_payment_modal"
              phx-value-contract-id={@contract_id}
              phx-value-month={@month}
              class="btn btn-primary shadow-lg shadow-primary/25 whitespace-nowrap"
            >
              <.icon name={@cta_icon} class="w-5 h-5 mr-2" />
              {@cta_text}
            </button>
          <% else %>
            <button
              phx-click="scroll_to_payments"
              class="btn btn-primary shadow-lg shadow-primary/25 whitespace-nowrap"
            >
              <.icon name={@cta_icon} class="w-5 h-5 mr-2" />
              {@cta_text}
            </button>
          <% end %>
        </div>
      </div>
      """
    end
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
    <div class="space-y-6">
      <%!-- Current & Unpaid Payments (Expanded by Default) --%>
      <%= if @has_unpaid do %>
        <div
          class="bg-base-100 rounded-2xl shadow-sm border border-base-200 overflow-hidden"
          id="current-payments"
        >
          <button
            phx-click="toggle_current"
            class="w-full px-6 py-4 flex items-center justify-between hover:bg-warning/10 transition-colors bg-warning/5"
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
            @current_expanded && "max-h-[2000px] opacity-100",
            !@current_expanded && "max-h-0 opacity-0"
          ]}>
            <div class="divide-y divide-base-200 border-t border-base-200">
              <%= for item <- @unpaid_items do %>
                <.payment_overview_item item={item} contract={@contract} scope={@scope} />
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
            class="w-full px-6 py-4 flex items-center justify-between hover:bg-base-200/50 transition-colors"
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
            @history_expanded && "max-h-[2000px] opacity-100",
            !@history_expanded && "max-h-0 opacity-0"
          ]}>
            <div class="divide-y divide-base-200 border-t border-base-200">
              <%= for item <- @paid_items do %>
                <.payment_overview_item
                  item={item}
                  contract={@contract}
                  scope={@scope}
                  show_actions={false}
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
    can_submit = assigns.item.status in [:unpaid, :partial] && show_actions

    visuals = payment_item_visuals(assigns.item, assigns.contract)

    assigns =
      assign(assigns,
        show_actions: show_actions,
        can_submit: can_submit,
        icon: visuals.icon,
        icon_bg: visuals.bg_color,
        icon_color: visuals.text_color
      )

    ~H"""
    <div class="px-6 py-4">
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <%!-- Left: Period Info --%>
        <div class="flex items-start gap-4">
          <%!-- Status Icon with unified styling --%>
          <div class={[
            "w-12 h-12 rounded-xl flex items-center justify-center flex-shrink-0",
            @icon_bg
          ]}>
            <.icon name={@icon} class={["w-6 h-6", @icon_color]} />
          </div>
          <div>
            <div class="flex items-center gap-2">
              <p class="font-semibold">Month {@item.payment_number}</p>
              <.month_status_badge status={@item.status} />
              <%= if @item.is_overdue do %>
                <span class="px-2 py-0.5 bg-error/10 text-error rounded-full text-xs font-medium">
                  Overdue
                </span>
              <% end %>
            </div>
            <p class="text-sm text-base-content/60">Due: {format_date(@item.due_date)}</p>
            <%= if @item.payments != [] do %>
              <div class="mt-2 space-y-1">
                <%= for payment <- @item.payments do %>
                  <div class="flex items-center gap-2 text-sm">
                    <.payment_badge status={payment.status} size={:sm} />
                    <span>{format_currency(payment.amount)}</span>
                    <%= if payment.rejection_reason do %>
                      <span class="text-error text-xs">({payment.rejection_reason})</span>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Right: Amount & Action --%>
        <div class="flex items-center justify-between sm:justify-end gap-4">
          <%!-- Mini Invoice Breakdown --%>
          <div class="text-right">
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

          <%= if @can_submit do %>
            <button
              phx-click="show_payment_modal"
              phx-value-contract-id={@contract.id}
              phx-value-month={@item.payment_number}
              class="btn btn-primary btn-sm whitespace-nowrap"
            >
              <.icon name="hero-plus" class="w-4 h-4 mr-1" /> Pay
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Contract Quick Access Component
  defp contract_quick_access(assigns) do
    days_remaining = Contracts.days_until_end(assigns.contract)

    assigns = assign(assigns, days_remaining: days_remaining)

    ~H"""
    <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 p-6">
      <div class="flex items-center gap-2 mb-4">
        <.icon name="hero-document-text" class="w-5 h-5 text-primary" />
        <h2 class="text-lg font-semibold">Contract Details</h2>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
        <%!-- Lease Period --%>
        <div>
          <p class="text-sm text-base-content/60 mb-1">Lease Period</p>
          <p class="font-medium">
            {format_date(@contract.start_date)} - {format_date(@contract.end_date)}
          </p>
          <%= if @days_remaining > 0 do %>
            <p class="text-xs text-base-content/50 mt-1">
              <%= if Contracts.ending_soon?(@contract) do %>
                <span class="text-warning">Ends in {@days_remaining} days</span>
              <% else %>
                {@days_remaining} days remaining
              <% end %>
            </p>
          <% end %>
        </div>

        <%!-- Monthly Rent --%>
        <div>
          <p class="text-sm text-base-content/60 mb-1">Monthly Rent</p>
          <p class="font-medium text-primary">{format_currency(@contract.rent)}</p>
        </div>

        <%!-- Payment Due Date --%>
        <div>
          <p class="text-sm text-base-content/60 mb-1">Payment Due</p>
          <p class="font-medium">Day {@contract.expiration_day} of each month</p>
        </div>

        <%!-- Property Info --%>
        <div>
          <p class="text-sm text-base-content/60 mb-1">Property</p>
          <p class="font-medium">{@contract.property.name}</p>
          <p class="text-xs text-base-content/50 truncate">{@contract.property.address}</p>
        </div>
      </div>

      <%= if @contract.notes && @contract.notes != "" do %>
        <div class="mt-4 pt-4 border-t border-base-200">
          <p class="text-sm text-base-content/60 mb-1">Notes</p>
          <p class="text-sm text-base-content/80">{@contract.notes}</p>
        </div>
      <% end %>
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

  defp has_pending_payment?(payments) do
    Enum.any?(payments, &(&1.status == :pending))
  end

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

  defp get_earliest_unpaid_month(scope, contract) do
    current_payment_num = Contracts.get_current_payment_number(contract)
    today = Date.utc_today()

    1..current_payment_num
    |> Enum.filter(fn num ->
      due_date = Contracts.calculate_due_date(contract, num)

      Date.compare(today, due_date) != :lt and
        not Payments.month_fully_paid?(scope, contract, num)
    end)
    |> List.first(current_payment_num)
  end

  # Calculates all display values for a trend bar item.
  # Returns a map with pre-computed values to simplify template logic.
  defp calculate_trend_bar_data(month_date, expected, received, max_expected) do
    month_label = Calendar.strftime(month_date, "%b %Y")
    expected_float = Decimal.to_float(expected)
    received_float = Decimal.to_float(received)
    expected_pct = min(expected_float / max_expected * 100, 100)

    received_pct =
      if expected_float > 0 do
        received_float / expected_float * 100
      else
        0
      end

    received_pct = min(received_pct, 100)

    %{
      month_label: month_label,
      expected: expected,
      received: received,
      expected_pct: expected_pct,
      received_pct: received_pct
    }
  end
end
