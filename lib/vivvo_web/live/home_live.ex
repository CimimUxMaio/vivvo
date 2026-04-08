defmodule VivvoWeb.HomeLive do
  @moduledoc """
  Main dashboard LiveView for both owners and tenants.

  Owners see analytics, property metrics, and pending payment validations.
  Tenants see their contract details and payment history.
  """
  use VivvoWeb, :live_view

  import VivvoWeb.Helpers.ContractHelpers
  import VivvoWeb.PaymentComponents, only: [file_chip: 1]
  import VivvoWeb.SubmitPaymentModal, only: [submit_payment_modal: 1]
  import VivvoWeb.UploadHelpers, only: [clear_upload_files: 1, process_upload_entry: 2]

  alias Vivvo.Accounts.Scope
  alias Vivvo.Contracts
  alias Vivvo.Payments

  # Number of months to show in income trend chart
  @trend_months 6

  @file_config Application.compile_env(:vivvo, Vivvo.Files)

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
       |> assign(:expanded_payment_items, MapSet.new())
       |> assign(:submitting_payment, nil)
       |> assign(:payment_form, nil)
       |> assign(:payment_summary, nil)
       |> allow_upload(:files,
         accept: Enum.map(@file_config[:allowed_extensions], &".#{&1}"),
         max_entries: @file_config[:max_files_per_payment],
         max_file_size: @file_config[:max_file_size]
       )}
    else
      # Owner view - new dashboard with streams for large collections
      socket =
        socket
        |> assign(:today, Date.utc_today())
        |> assign(:rejecting_payment, nil)
        |> assign(:expanded_pending_payments, MapSet.new())
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
  def handle_event("toggle_pending_payment", %{"payment_id" => payment_id}, socket) do
    expanded = socket.assigns.expanded_pending_payments
    id = String.to_integer(payment_id)

    new_expanded =
      if MapSet.member?(expanded, id) do
        MapSet.delete(expanded, id)
      else
        MapSet.put(expanded, id)
      end

    {:noreply, assign(socket, :expanded_pending_payments, new_expanded)}
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

      summary = calculate_payment_summary(contract, month_num)

      # Pre-populate with minimum of rent or remaining allowance
      initial_amount = Decimal.min(summary.rent, summary.remaining)
      initial_attrs = %{"amount" => initial_amount, "type" => :rent}

      changeset =
        Payments.change_payment(
          scope,
          %Vivvo.Payments.Payment{},
          initial_attrs,
          remaining_allowance: summary.remaining
        )

      {:noreply,
       socket
       |> assign(:submitting_payment, {contract, month_num, :rent})
       |> assign(:payment_form, to_form(changeset))
       |> assign(:payment_summary, summary)}
    else
      {:noreply, put_flash(socket, :error, "Contract not found")}
    end
  end

  @impl true
  def handle_event(
        "show_misc_payment_modal",
        %{"contract-id" => contract_id},
        socket
      ) do
    scope = socket.assigns.current_scope
    contract = Contracts.get_contract_for_tenant(scope, contract_id)

    if contract do
      # Miscellaneous payment - no payment_number needed
      initial_attrs = %{"amount" => "", "type" => :miscellaneous}

      changeset =
        Payments.change_payment(
          scope,
          %Vivvo.Payments.Payment{},
          initial_attrs
        )

      {:noreply,
       socket
       |> assign(:submitting_payment, {contract, nil, :miscellaneous})
       |> assign(:payment_form, to_form(changeset))
       |> assign(:payment_summary, nil)}
    else
      {:noreply, put_flash(socket, :error, "Contract not found")}
    end
  end

  @impl true
  def handle_event("close_payment_modal", _params, socket) do
    file_entries = socket.assigns.uploads.files.entries

    {:noreply,
     socket
     |> then(fn s ->
       # Cancel all pending uploads
       Enum.reduce(file_entries, s, fn entry, socket ->
         cancel_upload(socket, :files, entry.ref)
       end)
     end)
     |> assign(:submitting_payment, nil)
     |> assign(:payment_form, nil)
     |> assign(:payment_summary, nil)}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  @impl true
  def handle_event("validate_payment", %{"payment" => params}, socket) do
    scope = socket.assigns.current_scope
    {_contract, month, payment_type} = socket.assigns.submitting_payment

    # Normalize params with server-side payment type enforcement
    params = normalize_payment_params(params, payment_type, month)

    # Only validate with remaining allowance for rent payments
    opts =
      if payment_type == :rent,
        do: [remaining_allowance: socket.assigns.payment_summary.remaining],
        else: []

    changeset =
      Payments.change_payment(
        scope,
        %Vivvo.Payments.Payment{},
        params,
        opts
      )
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(payment_form: to_form(changeset))}
  end

  @impl true
  def handle_event("submit_payment", %{"payment" => params}, socket) do
    scope = socket.assigns.current_scope
    {contract, month, payment_type} = socket.assigns.submitting_payment

    # Normalize params with server-side payment type enforcement
    attrs =
      params
      |> Map.put("contract_id", contract.id)
      |> normalize_payment_params(payment_type, month)

    # Only validate remaining allowance for rent payments
    opts =
      if payment_type == :rent do
        summary = calculate_payment_summary(contract, month)
        [remaining_allowance: summary.remaining]
      else
        []
      end

    # Collect uploaded files
    uploaded_files =
      consume_uploaded_entries(socket, :files, &process_upload_entry/2)

    case Payments.create_payment(scope, attrs, uploaded_files, opts) do
      {:ok, _payment} ->
        clear_upload_files(uploaded_files)

        contracts = Contracts.list_contracts_for_tenant(scope)

        selected_contract =
          Enum.find(contracts, &(to_string(&1.id) == to_string(contract.id))) ||
            List.first(contracts)

        success_message =
          if payment_type == :rent,
            do: "Payment submitted successfully!",
            else: "Miscellaneous payment submitted successfully!"

        {:noreply,
         socket
         |> assign(:submitting_payment, nil)
         |> assign(:payment_form, nil)
         |> assign(:payment_summary, nil)
         |> assign(:contracts, contracts)
         |> assign(:selected_contract, selected_contract)
         |> put_flash(:info, success_message)}

      {:error, %Ecto.Changeset{} = changeset} ->
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
      |> assign(:expanded_pending_payments, MapSet.new())
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

  defp handle_reject_payment_result(socket, _scope, {:ok, payment}) do
    pending_payments =
      Enum.reject(socket.assigns.pending_payments, fn p -> p.id == payment.id end)

    socket =
      socket
      |> assign(:pending_payments, pending_payments)
      |> assign(:rejecting_payment, nil)
      |> assign(:pending_payments_empty?, pending_payments == [])
      |> assign(:expanded_pending_payments, MapSet.new())
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
    |> assign(:pending_payments, pending_payments)
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
          uploads={@uploads}
          contracts={@contracts}
          current_scope={@current_scope}
          selected_contract={@selected_contract}
          current_expanded={@current_expanded}
          history_expanded={@history_expanded}
          submitting_payment={@submitting_payment}
          payment_form={@payment_form}
          payment_summary={@payment_summary}
          expanded_payment_items={@expanded_payment_items}
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
          pending_payments={@pending_payments}
          rejecting_payment={@rejecting_payment}
          expanded_pending_payments={@expanded_pending_payments}
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
      <.page_header title="Dashboard" back_navigate={nil}>
        <:subtitle>
          Welcome back! Here's what's happening with your properties.
        </:subtitle>
      </.page_header>

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
        pending_payments={@pending_payments}
        expanded_pending_payments={@expanded_pending_payments}
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
    <div class="grid grid-cols-3 gap-4">
      <%!-- Properties --%>
      <.link navigate={~p"/properties"} class="block">
        <div class="bg-base-100 rounded-xl p-4 shadow-sm border border-base-200 hover:bg-base-200/50 cursor-pointer transition-colors duration-200">
          <div class="flex items-center justify-center sm:justify-start gap-3">
            <div class="p-2 bg-primary/10 rounded-lg flex items-center">
              <.icon name="hero-building-office" class="size-8 text-primary" />
            </div>
            <div>
              <p class="hidden sm:block text-sm text-base-content/60">Properties</p>
              <p class="text-2xl font-bold">{@summary.total_properties}</p>
            </div>
          </div>
        </div>
      </.link>

      <%!-- Contracts --%>
      <.link navigate={~p"/properties"} class="block">
        <div class="bg-base-100 rounded-xl p-4 shadow-sm border border-base-200 hover:bg-base-200/50 cursor-pointer transition-colors duration-200">
          <div class="flex items-center justify-center sm:justify-start gap-3">
            <div class="p-2 bg-success/10 rounded-lg flex items-center">
              <.icon name="hero-document-text" class="size-8 text-success" />
            </div>
            <div>
              <p class="hidden sm:block text-sm text-base-content/60">Contracts</p>
              <p class="text-2xl font-bold">{@summary.total_contracts}</p>
            </div>
          </div>
        </div>
      </.link>

      <%!-- Pending --%>
      <div
        class="cursor-pointer"
        phx-click={JS.dispatch("scroll_to", detail: %{id: "pending-payments"})}
        phx-keydown={JS.dispatch("scroll_to", detail: %{id: "pending-payments"})}
        phx-key="enter"
        role="link"
        tabindex="0"
      >
        <div class="bg-base-100 rounded-xl p-4 shadow-sm border border-base-200 hover:bg-base-200/50 transition-colors duration-200">
          <div class="flex items-center justify-center sm:justify-start gap-3">
            <div class="p-2 bg-warning/10 rounded-lg flex items-center">
              <.icon name="hero-clock" class="size-8 text-warning" />
            </div>
            <div>
              <p class="hidden sm:block text-sm text-base-content/60">Pending</p>
              <p class="text-2xl font-bold">{@payment_counts.pending}</p>
            </div>
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
    # Pre-compute all trend bar data
    trend_bars =
      Enum.map(assigns.income_trend, fn {month_date, expected, received} ->
        calculate_trend_bar_data(month_date, expected, received)
      end)

    assigns = assign(assigns, :trend_bars, trend_bars)

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
              <%!-- Collection progress bar --%>
              <div
                class={[
                  "absolute top-0 left-0 h-full rounded-l-lg transition-all duration-500",
                  bar.collection_pct >= 100 && "bg-success",
                  bar.collection_pct >= 50 && bar.collection_pct < 100 && "bg-warning",
                  bar.collection_pct < 50 && "bg-error"
                ]}
                style={"width: #{bar.collection_pct}%"}
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
      </div>
    </div>
    """
  end

  # Outstanding Aging Card Component with Pie Chart
  defp outstanding_aging_card(assigns) do
    # Prepare chart data with labels, values, and CSS variable names
    chart_data = [
      %{label: "Current", value: assigns.outstanding_aging.current, color: "--color-info"},
      %{label: "0-7 days", value: assigns.outstanding_aging.days_0_7, color: "--color-warning"},
      %{
        label: "8-30 days",
        value: assigns.outstanding_aging.days_8_30,
        color: "--color-warning",
        opacity: 70
      },
      %{label: "31+ days", value: assigns.outstanding_aging.days_31_plus, color: "--color-error"}
    ]

    assigns =
      assign(assigns,
        chart_data: chart_data,
        chart_data_json: Jason.encode!(chart_data)
      )

    ~H"""
    <div class="bg-base-100 rounded-2xl p-6 shadow-sm border border-base-200">
      <%!-- Header with total --%>
      <div class="flex flex-col sm:flex-row sm:items-center justify-between mb-3 sm:mb-6 gap-3">
        <div class="flex items-center gap-2">
          <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-primary" />
          <h2 class="text-lg font-semibold">Outstanding Balances</h2>
        </div>
        <span class="text-2xl font-bold text-accent self-center">
          {format_currency(@total_outstanding)}
        </span>
      </div>

      <%!-- Pie Chart --%>
      <div class="relative w-full aspect-square max-w-[300px] mx-auto mb-6">
        <canvas
          id="outstanding-balances-chart"
          phx-hook="PieChart"
          phx-update="ignore"
          data-chart-data={@chart_data_json}
        >
        </canvas>
      </div>

      <%!-- Legend --%>
      <div class="flex flex-wrap items-center justify-center gap-x-6 gap-y-2 mb-4 text-xs">
        <div class="flex items-center gap-1.5">
          <div class="w-3 h-3 rounded bg-info"></div>
          <span class="text-base-content/60">Current</span>
        </div>
        <div class="flex items-center gap-1.5">
          <div class="w-3 h-3 rounded bg-warning"></div>
          <span class="text-base-content/60">0-7 days</span>
        </div>
        <div class="flex items-center gap-1.5">
          <div class="w-3 h-3 rounded bg-warning/70"></div>
          <span class="text-base-content/60">8-30 days</span>
        </div>
        <div class="flex items-center gap-1.5">
          <div class="w-3 h-3 rounded bg-error"></div>
          <span class="text-base-content/60">31+ days</span>
        </div>
      </div>

      <%!-- Information message --%>
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
                <th class="px-4 py-3 text-center font-medium text-base-content/70 min-w-[100px] whitespace-nowrap">
                  Days
                </th>
                <th class="px-4 py-3 text-right font-medium text-base-content/70">Rent</th>
                <th class="px-4 py-3 text-right font-medium text-base-content/70">Income</th>
                <th class="px-4 py-3 text-right font-medium text-base-content/70">Expected</th>
                <th class="px-4 py-3 text-center font-medium text-base-content/70">Collection</th>
                <th class="px-4 py-3 text-center font-medium text-base-content/70">Avg Delay</th>
                <th class="px-4 py-3 text-center font-medium text-base-content/70">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-200">
              <%= for metric <- @property_metrics do %>
                <tr
                  phx-click={JS.navigate(~p"/properties/#{metric.property.id}")}
                  class="hover:bg-base-200/50 transition-colors cursor-pointer"
                >
                  <td class="px-4 py-3 min-w-[180px]">
                    <div class="font-medium whitespace-nowrap">{metric.property.name}</div>
                    <div class="text-xs text-base-content/50 truncate max-w-[200px]">
                      {metric.property.address}
                    </div>
                  </td>
                  <td class="px-4 py-3 text-center">
                    <%= cond do %>
                      <% metric.state == :occupied -> %>
                        <div class="inline-flex items-center gap-1.5 px-2 py-1 bg-success/10 text-success rounded-full text-xs font-medium">
                          Occupied
                        </div>
                      <% metric.state == :upcoming -> %>
                        <div class="inline-flex items-center gap-1.5 px-2 py-1 bg-info/10 text-info rounded-full text-xs font-medium">
                          Upcoming
                        </div>
                      <% true -> %>
                        <div class="inline-flex items-center gap-1.5 px-2 py-1 bg-base-300/30 text-base-content/60 rounded-full text-xs font-medium">
                          Vacant
                        </div>
                    <% end %>
                  </td>
                  <td class="px-4 py-3 text-center whitespace-nowrap">
                    <%= cond do %>
                      <% metric.state == :occupied -> %>
                        <.days_until_end_display days={metric.days_until_end} />
                      <% metric.state == :upcoming -> %>
                        <span class="text-info">Starts in {metric.days_until_start}d</span>
                      <% true -> %>
                        <span class="text-base-content/30">-</span>
                    <% end %>
                  </td>
                  <td class="px-4 py-3 text-right font-medium">
                    <%= if metric.state in [:occupied, :upcoming] do %>
                      {format_currency(Contracts.current_rent_value(metric.contract))}
                    <% else %>
                      <span class="text-base-content/30">-</span>
                    <% end %>
                  </td>
                  <td class="px-4 py-3 text-right font-medium">
                    <%= if metric.state == :occupied do %>
                      {format_currency(metric.total_income)}
                    <% else %>
                      <span class="text-base-content/30">-</span>
                    <% end %>
                  </td>
                  <td class="px-4 py-3 text-right text-base-content/70">
                    <%= if metric.state == :occupied do %>
                      {format_currency(metric.total_expected)}
                    <% else %>
                      <span class="text-base-content/30">-</span>
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
                    <% else %>
                      <div class="text-center">
                        <span class="text-base-content/30">-</span>
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
                    <% else %>
                      <span class="text-base-content/30">-</span>
                    <% end %>
                  </td>
                  <td class="px-4 py-3 text-center">
                    <%= if metric.state == :occupied do %>
                      <.property_status_badge collection_rate={metric.collection_rate} />
                    <% else %>
                      <span class="text-base-content/30">-</span>
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
          <.button navigate={~p"/properties/new"} variant="primary" class="btn-sm mt-4">
            <.icon name="hero-plus" class="w-4 h-4 mr-1" /> Add Property
          </.button>
        </div>
      <% end %>
    </div>
    """
  end

  defp days_until_end_display(assigns) do
    days = assigns.days

    {color_class, text} =
      cond do
        is_nil(days) ->
          {"text-base-content/30", "-"}

        days == 0 ->
          {"text-error", "Ending today"}

        days > 30 ->
          {"text-success", "#{days}d left"}

        days >= 7 ->
          {"text-warning", "#{days}d left"}

        true ->
          {"text-error", "#{days}d left"}
      end

    assigns = assign(assigns, color_class: color_class, text: text)

    ~H"""
    <span class={@color_class}>{@text}</span>
    """
  end

  # Payment Validation Queue Component
  defp payment_validation_queue(assigns) do
    ~H"""
    <div
      id="pending-payments"
      class="bg-base-100 rounded-2xl shadow-sm border border-base-200 overflow-hidden"
    >
      <div class="p-4 sm:p-6 border-b border-base-200">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <.icon name="hero-clipboard-document-check" class="w-5 h-5 text-primary" />
            <h2 class="text-base sm:text-lg font-semibold">Payment Validation Queue</h2>
          </div>
          <%= if not @pending_payments_empty? do %>
            <span class="px-3 py-1.5 bg-warning/10 text-warning rounded-full text-sm font-medium">
              {length(@pending_payments)} pending
            </span>
          <% end %>
        </div>
      </div>

      <%= if @pending_payments_empty? do %>
        <div class="p-8 sm:p-12 text-center">
          <div class="w-16 h-16 mx-auto mb-4 bg-success/10 rounded-full flex items-center justify-center">
            <.icon name="hero-check-circle" class="w-8 h-8 text-success" />
          </div>
          <p class="text-base-content/60 font-medium">No pending payments to validate</p>
          <p class="text-sm text-base-content/50 mt-1">
            All caught up! New payments will appear here.
          </p>
        </div>
      <% else %>
        <div id="pending-payments-list" class="divide-y divide-base-200">
          <div :for={payment <- @pending_payments} id={"payment-#{payment.id}"}>
            <.pending_payment_card
              payment={payment}
              expanded_pending_payments={@expanded_pending_payments}
            />
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp pending_payment_card(assigns) do
    contract = assigns.payment.contract
    is_misc_payment = assigns.payment.type != :rent

    # Only calculate expected amounts for rent payments
    {_due_date, expected_amount, payment_status} =
      if is_misc_payment do
        {nil, nil, :misc}
      else
        due_date = Contracts.calculate_due_date(contract, assigns.payment.payment_number)
        expected_amount = Contracts.current_rent_value(contract, due_date)
        paid_amount = assigns.payment.amount

        status =
          cond do
            Decimal.eq?(paid_amount, expected_amount) -> :correct
            Decimal.gt?(paid_amount, expected_amount) -> :overpaid
            true -> :underpaid
          end

        {due_date, expected_amount, status}
      end

    is_expanded = MapSet.member?(assigns.expanded_pending_payments, assigns.payment.id)

    # Determine category display
    category_info = payment_category_info(assigns.payment)

    assigns =
      assign(assigns,
        is_misc_payment: is_misc_payment,
        expected_amount: expected_amount,
        payment_status: payment_status,
        is_expanded: is_expanded,
        category_info: category_info
      )

    ~H"""
    <div class="group">
      <.payment_card_header {assigns} />
      <.payment_card_details payment={@payment} is_expanded={@is_expanded} />
    </div>
    """
  end

  # Returns category info (label, color, icon) for payment display
  defp payment_category_info(payment) do
    case payment.type do
      :rent ->
        %{label: "Rent", color: "bg-primary/10 text-primary", icon: "hero-home"}

      :miscellaneous ->
        case payment.category do
          :deposit ->
            %{label: "Deposit", color: "bg-success/10 text-success", icon: "hero-shield-check"}

          :maintenance ->
            %{label: "Maintenance", color: "bg-warning/10 text-warning", icon: "hero-wrench"}

          :services ->
            %{label: "Services", color: "bg-info/10 text-info", icon: "hero-bolt"}

          :other ->
            %{
              label: "Other",
              color: "bg-base-300 text-base-content/70",
              icon: "hero-question-mark-circle"
            }

          nil ->
            %{
              label: "Other",
              color: "bg-base-300 text-base-content/70",
              icon: "hero-question-mark-circle"
            }
        end
    end
  end

  # Card header component with unified design
  attr :payment, :map, required: true
  attr :is_misc_payment, :boolean, required: true
  attr :expected_amount, :any, required: true
  attr :payment_status, :atom, required: true
  attr :is_expanded, :boolean, required: true
  attr :category_info, :map, required: true

  defp payment_card_header(assigns) do
    tenant = assigns.payment.contract.tenant
    property = assigns.payment.contract.property

    has_details =
      (assigns.payment.notes && assigns.payment.notes != "") ||
        (assigns.payment.files && assigns.payment.files != [])

    assigns =
      assigns
      |> assign(:tenant, tenant)
      |> assign(:property, property)
      |> assign(:has_details, has_details)

    ~H"""
    <div
      phx-click={if @has_details, do: "toggle_pending_payment"}
      phx-value-payment_id={@payment.id}
      class={[
        "p-4 sm:p-5 transition-colors",
        @has_details && "cursor-pointer hover:bg-base-200/30",
        @is_expanded && "bg-base-200/20"
      ]}
    >
      <%!-- Mobile Layout --%>
      <.payment_card_header_mobile {assigns} />

      <%!-- Desktop Layout --%>
      <.payment_card_header_desktop {assigns} />
    </div>
    """
  end

  # Mobile card header layout
  attr :payment, :map, required: true
  attr :is_misc_payment, :boolean, required: true
  attr :expected_amount, :any, required: true
  attr :payment_status, :atom, required: true
  attr :is_expanded, :boolean, required: true
  attr :has_details, :boolean, required: true
  attr :category_info, :map, required: true
  attr :tenant, :map, required: true
  attr :property, :map, required: true

  defp payment_card_header_mobile(assigns) do
    ~H"""
    <div class="flex flex-col sm:hidden gap-4">
      <%!-- Top Row: Category Badge + Status + Actions --%>
      <div class="flex items-center justify-between gap-3">
        <%!-- Category Badge --%>
        <div class={[
          "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium",
          @category_info.color
        ]}>
          <.icon name={@category_info.icon} class="w-3.5 h-3.5" />
          {@category_info.label}
        </div>

        <%!-- Status Badge --%>
        <%= case @payment_status do %>
          <% :correct -> %>
            <span class="inline-flex items-center gap-1 text-xs text-success font-medium">
              <.icon name="hero-check-circle" class="w-4 h-4" /> Matches
            </span>
          <% :underpaid -> %>
            <span class="inline-flex items-center gap-1 text-xs text-warning font-medium">
              <.icon name="hero-exclamation-circle" class="w-4 h-4" />
              -{format_currency(Decimal.sub(@expected_amount, @payment.amount))}
            </span>
          <% :overpaid -> %>
            <span class="inline-flex items-center gap-1 text-xs text-info font-medium">
              <.icon name="hero-plus-circle" class="w-4 h-4" />
              +{format_currency(Decimal.sub(@payment.amount, @expected_amount))}
            </span>
          <% :misc -> %>
            <span class="text-xs text-base-content/50">Misc</span>
        <% end %>
      </div>

      <%!-- Tenant & Property Info --%>
      <div class="flex items-start gap-3">
        <div class="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
          <span class="text-sm font-bold text-primary">
            {String.first(@tenant.first_name)}{String.first(@tenant.last_name)}
          </span>
        </div>
        <div class="min-w-0 flex-1">
          <p class="font-semibold text-sm text-base-content">
            {@tenant.first_name} {@tenant.last_name}
          </p>
          <p class="text-xs text-base-content/60 truncate">
            {@property.name}
          </p>
        </div>
      </div>

      <%!-- Amount & Period Row --%>
      <div class="flex items-center justify-between bg-base-200/50 rounded-lg p-3">
        <div>
          <p class="text-xs text-base-content/50 mb-0.5">Amount Received</p>
          <p class={[
            "text-lg font-bold",
            @payment_status == :correct && "text-success",
            @payment_status == :underpaid && "text-warning",
            @payment_status == :overpaid && "text-info",
            @payment_status == :misc && "text-base-content"
          ]}>
            {format_currency(@payment.amount)}
          </p>
        </div>
        <div class="text-right">
          <%= if @is_misc_payment do %>
            <p class="text-xs text-base-content/50 mb-0.5">Submitted</p>
            <p class="text-sm font-medium">{@payment.inserted_at |> Calendar.strftime("%b %d")}</p>
          <% else %>
            <p class="text-xs text-base-content/50 mb-0.5">Period</p>
            <p class="text-sm font-medium">Month {@payment.payment_number}</p>
          <% end %>
        </div>
      </div>

      <%!-- Expected Amount (for rent payments) --%>
      <%= if not @is_misc_payment do %>
        <div class="flex items-center justify-between text-sm">
          <span class="text-base-content/60">Expected:</span>
          <span class="font-medium">{format_currency(@expected_amount)}</span>
        </div>
      <% end %>

      <%!-- Action Buttons --%>
      <div class="flex items-center gap-3 pt-1">
        <.button
          phx-click="accept_payment"
          phx-value-id={@payment.id}
          phx-click-stop
          class="btn-success flex-1"
        >
          <.icon name="hero-check" class="w-4 h-4 mr-1.5" /> Accept
        </.button>
        <.button
          phx-click="show_reject_modal"
          phx-value-payment-id={@payment.id}
          phx-click-stop
          class="btn-error flex-1"
        >
          <.icon name="hero-x-mark" class="w-4 h-4 mr-1.5" /> Reject
        </.button>
        <%= if @has_details do %>
          <button
            phx-click="toggle_pending_payment"
            phx-value-payment_id={@payment.id}
            phx-click-stop
            class={[
              "w-10 h-10 rounded-lg flex items-center justify-center transition-all duration-200",
              @is_expanded && "bg-primary/10",
              !@is_expanded && "bg-base-200"
            ]}
          >
            <.icon
              name="hero-chevron-down"
              class={[
                "w-5 h-5 transition-transform duration-200",
                @is_expanded && "rotate-180 text-primary",
                !@is_expanded && "text-base-content/50"
              ]}
            />
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  # Desktop card header layout
  attr :payment, :map, required: true
  attr :is_misc_payment, :boolean, required: true
  attr :expected_amount, :any, required: true
  attr :payment_status, :atom, required: true
  attr :is_expanded, :boolean, required: true
  attr :has_details, :boolean, required: true
  attr :category_info, :map, required: true
  attr :tenant, :map, required: true
  attr :property, :map, required: true

  defp payment_card_header_desktop(assigns) do
    ~H"""
    <div class="hidden sm:flex sm:items-center sm:justify-between gap-4">
      <%!-- Left: Tenant Info + Category --%>
      <div class="flex items-center gap-4 flex-1 min-w-0">
        <div class="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
          <span class="text-sm font-bold text-primary">
            {String.first(@tenant.first_name)}{String.first(@tenant.last_name)}
          </span>
        </div>
        <div class="min-w-0 flex-1">
          <div class="flex items-center gap-2 mb-0.5">
            <p class="font-semibold text-sm text-base-content truncate">
              {@tenant.first_name} {@tenant.last_name}
            </p>
            <%!-- Category Badge --%>
            <div class={[
              "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium",
              @category_info.color
            ]}>
              <.icon name={@category_info.icon} class="w-3 h-3" />
              {@category_info.label}
            </div>
          </div>
          <p class="text-xs text-base-content/60 truncate">
            {@property.name}
          </p>
        </div>
      </div>

      <%!-- Middle: Amount Info --%>
      <div class="flex items-center gap-6 flex-shrink-0">
        <%!-- Amount Received --%>
        <div class="text-right min-w-[100px]">
          <p class={[
            "text-base font-bold",
            @payment_status == :correct && "text-success",
            @payment_status == :underpaid && "text-warning",
            @payment_status == :overpaid && "text-info"
          ]}>
            {format_currency(@payment.amount)}
          </p>
          <%= case @payment_status do %>
            <% :correct -> %>
              <p class="text-xs text-success">Matches expected</p>
            <% :underpaid -> %>
              <p class="text-xs text-warning">
                -{format_currency(Decimal.sub(@expected_amount, @payment.amount))}
              </p>
            <% :overpaid -> %>
              <p class="text-xs text-info">
                +{format_currency(Decimal.sub(@payment.amount, @expected_amount))}
              </p>
            <% :misc -> %>
              <p class="text-xs text-base-content/50">
                {@payment.inserted_at |> Calendar.strftime("%b %d, %Y")}
              </p>
          <% end %>
        </div>

        <%!-- Expected Amount (for rent) --%>
        <%= if not @is_misc_payment do %>
          <div class="text-right min-w-[80px]">
            <p class="text-sm font-medium">{format_currency(@expected_amount)}</p>
            <p class="text-xs text-base-content/50">
              Period {@payment.payment_number}
            </p>
          </div>
        <% end %>
      </div>

      <%!-- Right: Actions --%>
      <div class="flex items-center gap-2 flex-shrink-0">
        <.button
          phx-click="accept_payment"
          phx-value-id={@payment.id}
          phx-click-stop
          class="btn-success btn-sm"
        >
          <.icon name="hero-check" class="w-4 h-4 mr-1" /> Accept
        </.button>
        <.button
          phx-click="show_reject_modal"
          phx-value-payment-id={@payment.id}
          phx-click-stop
          class="btn-error btn-sm"
        >
          <.icon name="hero-x-mark" class="w-4 h-4 mr-1" /> Reject
        </.button>
        <%= if @has_details do %>
          <button
            phx-click="toggle_pending_payment"
            phx-value-payment_id={@payment.id}
            phx-click-stop
            class={[
              "w-8 h-8 rounded-lg flex items-center justify-center transition-all duration-200 ml-1",
              @is_expanded && "bg-primary/10",
              !@is_expanded && "bg-base-200 hover:bg-base-300"
            ]}
          >
            <.icon
              name="hero-chevron-down"
              class={[
                "w-5 h-5 transition-transform duration-200",
                @is_expanded && "rotate-180 text-primary",
                !@is_expanded && "text-base-content/50"
              ]}
            />
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  # Expandable details section for payment card (notes and files)
  attr :payment, :map, required: true
  attr :is_expanded, :boolean, required: true

  defp payment_card_details(assigns) do
    has_notes = assigns.payment.notes && assigns.payment.notes != ""
    has_files = assigns.payment.files && assigns.payment.files != []
    has_details = has_notes || has_files

    assigns =
      assign(assigns,
        has_notes: has_notes,
        has_files: has_files,
        has_details: has_details
      )

    ~H"""
    <%= if @has_details do %>
      <div class={[
        "overflow-hidden transition-all duration-300 ease-in-out",
        "border-t border-base-200 bg-base-50/50",
        @is_expanded && "max-h-[400px] opacity-100",
        !@is_expanded && "max-h-0 opacity-0"
      ]}>
        <div class="p-4 sm:p-5 space-y-4">
          <%!-- Notes Section --%>
          <%= if @has_notes do %>
            <div class="flex items-start gap-3">
              <div class="p-1.5 bg-info/10 rounded-lg flex-shrink-0 mt-0.5 flex items-center">
                <.icon name="hero-document-text" class="w-4 h-4 text-info" />
              </div>
              <div class="flex-1 min-w-0">
                <p class="text-xs font-medium text-base-content/60 mb-1">Notes</p>
                <p class="text-sm text-base-content/80 leading-relaxed">{@payment.notes}</p>
              </div>
            </div>
          <% end %>

          <%!-- Attached Files Section --%>
          <%= if @has_files do %>
            <div class="flex items-start gap-3">
              <div class="p-1.5 bg-primary/10 rounded-lg flex-shrink-0 mt-0.5 flex items-center">
                <.icon name="hero-paper-clip" class="w-4 h-4 text-primary" />
              </div>
              <div class="flex-1 min-w-0">
                <p class="text-xs font-medium text-base-content/60 mb-2">
                  Attached Files ({length(@payment.files)})
                </p>
                <div class="flex flex-wrap gap-2">
                  <%= for file <- @payment.files do %>
                    <.file_chip file={file} />
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  # Tenant Dashboard Component (redesigned per issue #14)
  defp tenant_dashboard(assigns) do
    ~H"""
    <div class="space-y-6 sm:space-y-8">
      <%= if @contracts != [] do %>
        <% contract = @selected_contract || List.first(@contracts)
        contract_status = Contracts.contract_status(contract)
        payment_status = Contracts.contract_payment_status(@current_scope, contract)
        total_due = Contracts.total_amount_due(@current_scope, contract)
        earliest_due = Contracts.earliest_due_date(@current_scope, contract)
        payment_statuses = Contracts.get_payment_statuses(@current_scope, contract)
        next_due_date = Contracts.next_payment_date(contract) %>

        <%!-- Page Header with New Misc Payment Action --%>
        <.page_header title="My Rentals" back_navigate={nil}>
          <:action>
            <.button
              phx-click="show_misc_payment_modal"
              phx-value-contract-id={contract.id}
              variant="primary"
            >
              <.icon name="hero-plus" class="w-4 h-4 mr-1" /> New Payment
            </.button>
          </:action>
        </.page_header>

        <%!-- Property Switcher for Multiple Contracts --%>
        <%= if length(@contracts) > 1 do %>
          <.property_switcher contracts={@contracts} selected_contract={@selected_contract} />
        <% end %>

        <%!-- A. Header: Current Situation Snapshot --%>
        <.situation_snapshot
          contract={contract}
          contract_status={contract_status}
          payment_status={payment_status}
          total_due={total_due}
          earliest_due={earliest_due}
          next_due_date={next_due_date}
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
          scope={@current_scope}
          current_expanded={@current_expanded}
          history_expanded={@history_expanded}
          expanded_payment_items={@expanded_payment_items}
        />

        <%!-- D. Contract & Property Quick Access --%>
        <.contract_quick_access contract={contract} contract_status={contract_status} />

        <%!-- Submit Payment Modal --%>
        <%= if @submitting_payment do %>
          <.submit_payment_modal
            id="submit-payment-modal"
            uploads={@uploads}
            submitting_payment={@submitting_payment}
            payment_summary={@payment_summary}
            form={@payment_form}
            submit_event="submit_payment"
            close_event="close_payment_modal"
            validation_event="validate_payment"
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

  # Primary Action Zone Component
  defp primary_action_zone(assigns) do
    has_amount_due? = Decimal.gt?(assigns.total_due, Decimal.new(0))

    cta_info =
      cond do
        # PRIORITY 1: Submit payment takes precedence over viewing pending
        has_amount_due? ->
          month = get_earliest_unpaid_month(assigns.contract)
          build_submit_payment_cta(month, assigns.contract)

        # PRIORITY 2: Check if any payment is pending validation (only when no amount due)
        has_pending_payment?(assigns.contract.payments) ->
          {:view_pending, "View Pending Payment", "hero-eye", nil, nil}

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
            <.button
              phx-click="show_payment_modal"
              phx-value-contract-id={@contract_id}
              phx-value-month={@month}
              variant="primary"
              class="shadow-lg shadow-primary/25 whitespace-nowrap"
            >
              <.icon name={@cta_icon} class="w-5 h-5 mr-2" />
              {@cta_text}
            </.button>
          <% else %>
            <.button
              phx-click={JS.dispatch("scroll_to", detail: %{id: "current-payments"})}
              variant="primary"
              class="shadow-lg shadow-primary/25 whitespace-nowrap"
            >
              <.icon name={@cta_icon} class="w-5 h-5 mr-2" />
              {@cta_text}
            </.button>
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
            @current_expanded && "max-h-[600px] opacity-100 overflow-y-auto",
            !@current_expanded && "max-h-0 opacity-0"
          ]}>
            <div class="divide-y divide-base-200 border-t border-base-200">
              <%= for item <- @unpaid_items do %>
                <.payment_overview_item
                  item={item}
                  contract={@contract}
                  scope={@scope}
                  expanded_items={@expanded_payment_items}
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
            @history_expanded && "max-h-[600px] opacity-100 overflow-y-auto",
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
    can_submit = assigns.item.status in [:unpaid, :partial] && show_actions
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
              {format_currency(Contracts.current_rent_value(@contract))}
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

  defp has_pending_payment?(payments) do
    Enum.any?(payments, &(&1.status == :pending))
  end

  # Builds submit payment CTA or falls back to pending payment check
  defp build_submit_payment_cta(nil, contract) do
    if has_pending_payment?(contract.payments) do
      {:view_pending, "View Pending Payment", "hero-eye", nil, nil}
    else
      nil
    end
  end

  defp build_submit_payment_cta(month, contract) do
    {:submit_payment, "Submit Payment", "hero-credit-card", contract.id, month}
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

  defp get_earliest_unpaid_month(contract) do
    current_payment_num = Contracts.get_current_payment_number(contract)
    today = Date.utc_today()

    1..current_payment_num
    |> Enum.filter(fn num ->
      due_date = Contracts.calculate_due_date(contract, num)

      # Skip future months
      if Date.compare(today, due_date) == :lt do
        false
      else
        # Check if month still has remaining amount to pay
        # (considering both accepted AND pending payments)
        remaining = get_remaining_amount(contract, num)
        Decimal.gt?(remaining, Decimal.new(0))
      end
    end)
    |> List.first()
  end

  # Calculates all display values for a trend bar item.
  # Returns a map with pre-computed values to simplify template logic.
  defp calculate_trend_bar_data(month_date, expected, received) do
    month_label = Calendar.strftime(month_date, "%b %Y")
    expected_float = Decimal.to_float(expected)
    received_float = Decimal.to_float(received)

    collection_pct =
      if expected_float > 0 do
        min(received_float / expected_float * 100, 100)
      else
        0
      end

    %{
      month_label: month_label,
      expected: expected,
      received: received,
      collection_pct: collection_pct
    }
  end

  # Calculates payment totals for a specific month from preloaded contract payments.
  # Returns {accepted_total, pending_total} to avoid N+1 queries.
  defp calculate_payment_totals(contract, month) do
    contract.payments
    |> Enum.filter(&(&1.type == :rent and &1.payment_number == month))
    |> Enum.reduce({Decimal.new(0), Decimal.new(0)}, fn payment, {accepted, pending} ->
      case payment.status do
        :accepted -> {Decimal.add(accepted, payment.amount), pending}
        :pending -> {accepted, Decimal.add(pending, payment.amount)}
        _ -> {accepted, pending}
      end
    end)
  end

  # Returns the remaining amount to pay for a specific month.
  # This is the efficient single-purpose function for checking if payment is needed.
  defp get_remaining_amount(contract, month) do
    {accepted_total, pending_total} = calculate_payment_totals(contract, month)
    due_date = Contracts.calculate_due_date(contract, month)
    rent = Contracts.current_rent_value(contract, due_date)
    Decimal.sub(rent, Decimal.add(accepted_total, pending_total))
  end

  # Returns a full summary map for display purposes (templates).
  # Use get_remaining_amount/2 when you only need the remaining balance.
  defp calculate_payment_summary(contract, month) do
    {accepted_total, pending_total} = calculate_payment_totals(contract, month)
    due_date = Contracts.calculate_due_date(contract, month)
    rent = Contracts.current_rent_value(contract, due_date)
    remaining = Decimal.sub(rent, Decimal.add(accepted_total, pending_total))

    %{
      rent: rent,
      accepted_total: accepted_total,
      pending_total: pending_total,
      remaining: remaining,
      due_date: due_date
    }
  end

  # Normalizes payment parameters based on payment type.
  # Enforces server-side payment type and sets appropriate payment_number.
  # - For rent payments: sets payment_number to the month
  # - For misc payments: sets payment_number to nil
  defp normalize_payment_params(params, payment_type, month) do
    params
    |> Map.put("type", to_string(payment_type))
    |> Map.put("payment_number", if(payment_type == :rent, do: month))
  end
end
