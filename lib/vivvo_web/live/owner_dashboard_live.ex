defmodule VivvoWeb.OwnerDashboardLive do
  @moduledoc """
  Owner dashboard LiveView showing analytics, property metrics, and pending payments.
  """
  use VivvoWeb, :live_view

  import VivvoWeb.PaymentComponents, only: [file_chip: 1]

  alias Vivvo.Contracts
  alias Vivvo.Payments

  # Number of months to show in income trend chart
  @trend_months 6

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    # Subscribe to payments for real-time updates
    if connected?(socket) do
      Payments.subscribe_payments(scope)
    end

    socket =
      socket
      |> assign(:today, Date.utc_today())
      |> assign(:rejecting_payment, nil)
      |> assign(:expanded_pending_payments, MapSet.new())
      |> refresh_dashboard_data(scope)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # PubSub handlers for real-time payment updates
  @impl true
  def handle_info({event, %Vivvo.Payments.Payment{}}, socket)
      when event in [:created, :updated, :deleted] do
    scope = socket.assigns.current_scope
    {:noreply, refresh_owner_dashboard(socket, scope)}
  end

  @impl true
  def handle_info({:flash, type, message}, socket) do
    {:noreply, put_flash(socket, type, message)}
  end

  @impl true
  def handle_event("accept_payment", %{"id" => payment_id}, socket) do
    scope = socket.assigns.current_scope
    do_accept_payment(socket, scope, payment_id)
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
  def handle_event("set_rejecting_payment", %{"payment-id" => payment_id}, socket) do
    scope = socket.assigns.current_scope

    case Payments.get_payment(scope, payment_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Payment not found")}

      payment ->
        {:noreply,
         socket
         |> assign(:rejecting_payment, payment)
         |> push_modal_open("reject-payment-modal")}
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

  defp refresh_owner_dashboard(socket, scope) do
    socket
    |> assign(:expanded_pending_payments, MapSet.new())
    |> refresh_dashboard_data(scope)
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
      <div class="space-y-8">
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
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
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
        <.live_component
          module={VivvoWeb.RejectPaymentModal}
          id="reject-payment-modal"
          payment={@rejecting_payment}
          current_scope={@current_scope}
        />
      </div>
    </Layouts.app>
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
        <div class="overflow-x-auto scrollbar-hide">
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
                      {format_currency(Contracts.latest_rent_value(metric.contract))}
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
        expected_amount = Contracts.latest_rent_value(contract, due_date)
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
          phx-click={JS.push("set_rejecting_payment", value: %{"payment-id" => @payment.id})}
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
        <% else %>
          <div class="w-10 h-10"></div>
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
          phx-click={JS.push("set_rejecting_payment", value: %{"payment-id" => @payment.id})}
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
        <% else %>
          <div class="w-8 h-8 ml-1"></div>
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
        "border-t border-base-200 bg-base-200/50",
        @is_expanded && "opacity-100",
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
end
