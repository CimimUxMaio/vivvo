defmodule VivvoWeb.HomeLive do
  use VivvoWeb, :live_view

  alias Vivvo.Accounts.Scope
  alias Vivvo.Contracts
  alias Vivvo.Payments

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if Scope.tenant?(scope) do
      # Tenant view - existing logic
      contracts = Contracts.list_contracts_for_tenant(scope)
      socket = assign(socket, :contracts, contracts)
      {:ok, socket}
    else
      # Owner view - new dashboard with streams for large collections
      socket =
        socket
        |> assign(:today, Date.utc_today())
        |> refresh_dashboard_data(scope)

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("accept_payment", %{"id" => payment_id}, socket) do
    scope = socket.assigns.current_scope

    # Only owners can accept payments
    if Scope.owner?(scope) do
      payment = Payments.get_payment(scope, payment_id)

      case Payments.accept_payment(scope, payment) do
        {:ok, _payment} ->
          socket =
            socket
            |> refresh_dashboard_data(scope)
            |> put_flash(:info, "Payment accepted successfully")

          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to accept payment")}
      end
    else
      {:noreply, put_flash(socket, :error, "Unauthorized action")}
    end
  end

  @impl true
  def handle_event("reject_payment", %{"id" => payment_id, "reason" => reason}, socket) do
    scope = socket.assigns.current_scope

    # Only owners can reject payments
    if Scope.owner?(scope) do
      payment = Payments.get_payment(scope, payment_id)

      case Payments.reject_payment(scope, payment, reason) do
        {:ok, _payment} ->
          socket =
            socket
            |> refresh_dashboard_data(scope)
            |> put_flash(:info, "Payment rejected")

          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to reject payment")}
      end
    else
      {:noreply, put_flash(socket, :error, "Unauthorized action")}
    end
  end

  defp refresh_dashboard_data(socket, scope) do
    today = Date.utc_today()
    pending_payments = Payments.pending_payments_for_validation(scope)

    socket
    |> assign(:expected_income, Payments.expected_income_for_month(scope, today))
    |> assign(:received_income, Payments.received_income_for_month(scope, today))
    |> assign(:outstanding_balance, Payments.outstanding_balance_for_month(scope, today))
    |> assign(:collection_rate, Payments.collection_rate_for_month(scope, today))
    |> assign(:income_trend, Payments.income_trend(scope, 6))
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
        <.tenant_dashboard contracts={@contracts} current_scope={@current_scope} />
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
      <.payment_validation_queue pending_payments_empty?={@pending_payments_empty?} />
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
            Decimal.compare(@outstanding_balance, Decimal.new(0)) == :gt && "text-error",
            Decimal.compare(@outstanding_balance, Decimal.new(0)) == :eq && "text-success"
          ]}>
            {format_currency(@outstanding_balance)}
          </p>
          <p class="text-sm text-base-content/50">
            <%= cond do %>
              <% Decimal.compare(@outstanding_balance, Decimal.new(0)) == :gt -> %>
                Still to collect
              <% Decimal.compare(@outstanding_balance, Decimal.new(0)) == :lt -> %>
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
        <%= if Decimal.compare(@outstanding_balance, Decimal.new(0)) == :gt do %>
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

    assigns = assign(assigns, :max_expected, max_expected)

    ~H"""
    <div class="bg-base-100 rounded-2xl p-6 shadow-sm border border-base-200">
      <div class="flex items-center gap-2 mb-6">
        <.icon name="hero-chart-bar" class="w-5 h-5 text-primary" />
        <h2 class="text-lg font-semibold">Income Trend</h2>
      </div>

      <div class="space-y-4">
        <%= for {month_date, expected, received} <- @income_trend do %>
          <% month_label = Calendar.strftime(month_date, "%b %Y")
          expected_float = Decimal.to_float(expected)
          received_float = Decimal.to_float(received)
          expected_pct = min(expected_float / @max_expected * 100, 100)
          received_pct = if expected_float > 0, do: received_float / expected_float * 100, else: 0
          received_pct = min(received_pct, 100) %>
          <div class="space-y-2">
            <div class="flex justify-between text-sm">
              <span class="text-base-content/70">{month_label}</span>
              <span class="font-medium">
                {format_currency(received)} / {format_currency(expected)}
              </span>
            </div>
            <div class="relative h-8 bg-base-200 rounded-lg overflow-hidden">
              <%!-- Expected amount bar (background) --%>
              <div
                class="absolute top-0 left-0 h-full bg-base-300/50 rounded-l-lg"
                style={"width: #{expected_pct}%"}
              >
              </div>
              <%!-- Received amount bar --%>
              <div
                class={[
                  "absolute top-0 left-0 h-full rounded-l-lg transition-all duration-500",
                  received_pct >= 100 && "bg-success",
                  received_pct >= 50 && received_pct < 100 && "bg-warning",
                  received_pct < 50 && "bg-error"
                ]}
                style={"width: #{received_pct}%"}
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

      <%= if Decimal.compare(@total_outstanding, Decimal.new(0)) == :gt do %>
        <div class="mt-4 p-3 bg-warning/10 rounded-lg border border-warning/20">
          <div class="flex items-start gap-2">
            <.icon name="hero-light-bulb" class="w-5 h-5 text-warning flex-shrink-0 mt-0.5" />
            <p class="text-sm text-base-content/80">
              Consider following up on
              <%= if Decimal.compare(@outstanding_aging.days_31_plus, Decimal.new(0)) == :gt do %>
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
                <th class="px-4 py-3 text-right font-medium text-base-content/70">Income</th>
                <th class="px-4 py-3 text-right font-medium text-base-content/70">Expected</th>
                <th class="px-4 py-3 text-center font-medium text-base-content/70">Collection</th>
                <th class="px-4 py-3 text-center font-medium text-base-content/70">Avg Delay</th>
                <th class="px-4 py-3 text-center font-medium text-base-content/70">Tenants</th>
                <th class="px-4 py-3 text-center font-medium text-base-content/70">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-200">
              <%= for metric <- @property_metrics do %>
                <tr class="hover:bg-base-200/30 transition-colors">
                  <td class="px-4 py-3">
                    <div class="font-medium">{metric.property.name}</div>
                    <div class="text-xs text-base-content/50 truncate max-w-[150px]">
                      {metric.property.address}
                    </div>
                  </td>
                  <td class="px-4 py-3 text-right font-medium">
                    {format_currency(metric.total_income)}
                  </td>
                  <td class="px-4 py-3 text-right text-base-content/70">
                    {format_currency(metric.total_expected)}
                  </td>
                  <td class="px-4 py-3">
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
                          style={"width: #{metric.collection_rate}%"}
                        >
                        </div>
                      </div>
                      <span class="text-xs font-medium w-10 text-right">
                        {Float.round(metric.collection_rate, 0)}%
                      </span>
                    </div>
                  </td>
                  <td class="px-4 py-3 text-center">
                    <%= if metric.avg_delay_days > 0 do %>
                      <span class="text-error">{metric.avg_delay_days}d</span>
                    <% else %>
                      <span class="text-success">On time</span>
                    <% end %>
                  </td>
                  <td class="px-4 py-3 text-center">
                    <span class="inline-flex items-center justify-center w-8 h-8 rounded-full bg-base-200 text-sm font-medium">
                      {metric.active_tenants}
                    </span>
                  </td>
                  <td class="px-4 py-3 text-center">
                    <.property_status_badge collection_rate={metric.collection_rate} />
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
      <div class="p-6 border-b border-base-200">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <.icon name="hero-clipboard-document-check" class="w-5 h-5 text-primary" />
            <h2 class="text-lg font-semibold">Payment Validation Queue</h2>
          </div>
          <%= if not @pending_payments_empty? do %>
            <span class="px-3 py-1 bg-warning/10 text-warning rounded-full text-sm font-medium">
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
        Decimal.compare(paid_amount, expected_amount) == :eq -> :correct
        Decimal.compare(paid_amount, expected_amount) == :gt -> :overpaid
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
    <div class="p-4 sm:p-6 hover:bg-base-200/30 transition-colors">
      <div class="flex flex-col lg:flex-row lg:items-center gap-4">
        <%!-- Payment Info --%>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-3 mb-2">
            <div class="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
              <span class="text-sm font-bold text-primary">
                {String.first(@tenant.first_name)}{String.first(@tenant.last_name)}
              </span>
            </div>
            <div class="min-w-0">
              <p class="font-medium truncate">
                {@tenant.first_name} {@tenant.last_name}
              </p>
              <p class="text-sm text-base-content/60 truncate">
                {@property.name}
              </p>
            </div>
          </div>
          <div class="flex flex-wrap items-center gap-2 text-sm text-base-content/70">
            <span class="inline-flex items-center gap-1">
              <.icon name="hero-calendar" class="w-4 h-4" /> Period {@payment.payment_number}
            </span>
            <span class="text-base-content/30">•</span>
            <span>{@payment.inserted_at |> Calendar.strftime("%b %d, %Y")}</span>
          </div>
        </div>

        <%!-- Amount Comparison --%>
        <div class="flex items-center gap-4">
          <div class="text-right">
            <p class={[
              "text-lg font-bold",
              @payment_status == :correct && "text-success",
              @payment_status == :underpaid && "text-warning",
              @payment_status == :overpaid && "text-info"
            ]}>
              {format_currency(@payment.amount)}
            </p>
            <p class="text-sm text-base-content/60">
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
        </div>

        <%!-- Actions --%>
        <div class="flex items-center gap-2">
          <button
            phx-click="accept_payment"
            phx-value-id={@payment.id}
            class="btn btn-success btn-sm"
          >
            <.icon name="hero-check" class="w-4 h-4 mr-1" /> Accept
          </button>
          <div class="dropdown dropdown-end">
            <button class="btn btn-ghost btn-sm">
              <.icon name="hero-x-mark" class="w-4 h-4 mr-1" /> Reject
            </button>
            <ul class="dropdown-content menu p-2 shadow-lg bg-base-100 rounded-box w-52 z-50">
              <li>
                <button
                  phx-click="reject_payment"
                  phx-value-id={@payment.id}
                  phx-value-reason="Incorrect amount"
                >
                  Incorrect amount
                </button>
              </li>
              <li>
                <button
                  phx-click="reject_payment"
                  phx-value-id={@payment.id}
                  phx-value-reason="Missing documentation"
                >
                  Missing documentation
                </button>
              </li>
              <li>
                <button
                  phx-click="reject_payment"
                  phx-value-id={@payment.id}
                  phx-value-reason="Duplicate payment"
                >
                  Duplicate payment
                </button>
              </li>
              <li>
                <button phx-click="reject_payment" phx-value-id={@payment.id} phx-value-reason="Other">
                  Other reason
                </button>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <%= if @payment.notes && @payment.notes != "" do %>
        <div class="mt-3 p-3 bg-base-200/50 rounded-lg">
          <p class="text-sm text-base-content/70">
            <span class="font-medium">Note:</span> {@payment.notes}
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  # Tenant Dashboard Component (existing functionality)
  defp tenant_dashboard(assigns) do
    ~H"""
    <div class="space-y-8">
      <%= if @contracts != [] do %>
        <%= for contract <- @contracts do %>
          <div class="space-y-6">
            <%!-- Contract Card with Status Badge --%>
            <.contract_card
              contract={contract}
              payment_status={Contracts.contract_payment_status(@current_scope, contract)}
            />

            <%!-- Monthly Payments List --%>
            <.monthly_payments_section
              contract={contract}
              months={Contracts.get_months_up_to_current(contract)}
              scope={@current_scope}
            />

            <%!-- Payment History Table --%>
            <.payment_history_section payments={contract.payments} />
          </div>
        <% end %>
      <% else %>
        <.no_contract_message />
      <% end %>
    </div>
    """
  end

  # Contract Card Component (existing)
  defp contract_card(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 p-6">
      <div class="flex justify-between items-start mb-4">
        <h1 class="text-xl font-bold">My Lease</h1>
        <.payment_status_badge status={@payment_status} />
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div>
          <p class="text-sm text-base-content/60">Property</p>
          <p class="text-lg font-semibold">{@contract.property.name}</p>
          <p class="text-sm text-base-content/50">{@contract.property.address}</p>
        </div>
        <div>
          <p class="text-sm text-base-content/60">Monthly Rent</p>
          <p class="text-lg font-semibold text-primary">{format_currency(@contract.rent)}</p>
        </div>
        <div>
          <p class="text-sm text-base-content/60">Lease Period</p>
          <p class="text-lg font-semibold">{format_date(@contract.start_date)}</p>
          <p class="text-sm text-base-content/50">to {format_date(@contract.end_date)}</p>
        </div>
      </div>
    </div>
    """
  end

  # Monthly Payments Section (existing)
  defp monthly_payments_section(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 p-6">
      <h2 class="text-lg font-semibold mb-4">Monthly Payments</h2>

      <div class="space-y-4">
        <%= for month <- @months do %>
          <.month_card
            contract={@contract}
            month={month}
            scope={@scope}
          />
        <% end %>
      </div>
    </div>
    """
  end

  # Month Card Component (existing)
  defp month_card(assigns) do
    month_status = Payments.get_month_status(assigns.scope, assigns.contract, assigns.month)

    total_paid =
      Payments.total_accepted_for_month(assigns.scope, assigns.contract.id, assigns.month)

    due_date = Contracts.calculate_due_date(assigns.contract, assigns.month)
    current_payment_num = Contracts.get_current_payment_number(assigns.contract)
    can_submit = month_status in [:unpaid, :partial] and assigns.month <= current_payment_num

    month_payments =
      Enum.filter(assigns.contract.payments, &(&1.payment_number == assigns.month))

    assigns =
      assign(assigns,
        month_status: month_status,
        total_paid: total_paid,
        due_date: due_date,
        can_submit: can_submit,
        month_payments: month_payments
      )

    ~H"""
    <div class={[
      "border rounded-xl p-4 transition-colors",
      @month_status == :paid && "border-success bg-success/5",
      @month_status == :partial && "border-warning bg-warning/5",
      @month_status == :unpaid && "border-base-300"
    ]}>
      <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-3">
        <div>
          <h3 class="font-semibold">Month {@month}</h3>
          <p class="text-sm text-base-content/70">Due: {format_date(@due_date)}</p>
        </div>
        <div class="text-right">
          <p class="text-sm">
            <span class="font-medium">{format_currency(@total_paid)}</span>
            <span class="text-base-content/60"> of </span>
            <span class="font-medium">{format_currency(@contract.rent)}</span>
          </p>
          <.month_status_badge status={@month_status} />
        </div>
      </div>

      <%!-- Payment Submissions --%>
      <%= if @month_payments != [] do %>
        <div class="border-t border-base-200 my-3 pt-3 space-y-2">
          <%= for payment <- @month_payments do %>
            <.payment_submission_item payment={payment} />
          <% end %>
        </div>
      <% end %>

      <%= if @can_submit do %>
        <div class="flex justify-end mt-3">
          <.link
            navigate={~p"/contracts/#{@contract.id}/payments/new?month=#{@month}"}
            class="btn btn-primary btn-sm"
          >
            <.icon name="hero-plus" class="w-4 h-4 mr-1" /> Submit Payment
          </.link>
        </div>
      <% end %>
    </div>
    """
  end

  # Payment Submission Item Component (existing)
  defp payment_submission_item(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-2 p-3 bg-base-100 rounded-lg border border-base-200">
      <div class="flex flex-wrap items-center gap-3">
        <.payment_badge status={@payment.status} />
        <span class="font-medium">{format_currency(@payment.amount)}</span>
        <%= if @payment.notes && @payment.notes != "" do %>
          <span class="text-sm text-base-content/60">- {@payment.notes}</span>
        <% end %>
      </div>
      <%= if @payment.rejection_reason do %>
        <span class="text-error text-sm px-2 py-1 bg-error/10 rounded">
          {@payment.rejection_reason}
        </span>
      <% end %>
    </div>
    """
  end

  # Payment History Section (existing)
  defp payment_history_section(assigns) do
    sorted_payments = Enum.sort_by(assigns.payments, & &1.inserted_at, :desc)

    assigns = assign(assigns, sorted_payments: sorted_payments)

    ~H"""
    <div class="bg-base-100 rounded-2xl shadow-sm border border-base-200 p-6">
      <h2 class="text-lg font-semibold mb-4">Payment History</h2>

      <%= if @sorted_payments != [] do %>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="bg-base-200/50">
              <tr>
                <th class="px-4 py-3 text-left font-medium text-base-content/70">Date</th>
                <th class="px-4 py-3 text-left font-medium text-base-content/70">Month</th>
                <th class="px-4 py-3 text-right font-medium text-base-content/70">Amount</th>
                <th class="px-4 py-3 text-center font-medium text-base-content/70">Status</th>
                <th class="px-4 py-3 text-left font-medium text-base-content/70">Notes</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-200">
              <%= for payment <- @sorted_payments do %>
                <tr class="hover:bg-base-200/30">
                  <td class="px-4 py-3">{format_datetime(payment.inserted_at)}</td>
                  <td class="px-4 py-3">Month {payment.payment_number}</td>
                  <td class="px-4 py-3 text-right font-medium">{format_currency(payment.amount)}</td>
                  <td class="px-4 py-3 text-center"><.payment_badge status={payment.status} /></td>
                  <td class="px-4 py-3 text-base-content/70 max-w-xs truncate">
                    {payment.notes || "-"}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% else %>
        <div class="text-center py-8">
          <p class="text-base-content/60">No payment history yet.</p>
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
end
