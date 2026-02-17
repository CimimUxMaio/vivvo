defmodule VivvoWeb.HomeLive do
  use VivvoWeb, :live_view

  alias Vivvo.Accounts.Scope
  alias Vivvo.Contracts
  alias Vivvo.Payments

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    contracts =
      if Scope.tenant?(scope) do
        Contracts.list_contracts_for_tenant(scope)
      else
        []
      end

    socket = assign(socket, :contracts, contracts)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%= if Scope.tenant?(@current_scope) do %>
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
      <% else %>
        Home: Owner
      <% end %>
    </Layouts.app>
    """
  end

  # Contract Card Component
  defp contract_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-lg">
      <div class="card-body">
        <div class="flex justify-between items-start mb-4">
          <h1 class="card-title text-2xl">My Lease</h1>
          <.payment_status_badge status={@payment_status} />
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div class="stat">
            <div class="stat-title">Property</div>
            <div class="stat-value text-lg">{@contract.property.name}</div>
            <div class="stat-desc">{@contract.property.address}</div>
          </div>
          <div class="stat">
            <div class="stat-title">Monthly Rent</div>
            <div class="stat-value text-lg text-primary">{format_currency(@contract.rent)}</div>
          </div>
          <div class="stat">
            <div class="stat-title">Lease Period</div>
            <div class="stat-value text-lg">{format_date(@contract.start_date)}</div>
            <div class="stat-desc">to {format_date(@contract.end_date)}</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Monthly Payments Section
  defp monthly_payments_section(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-lg">
      <div class="card-body">
        <h2 class="card-title text-xl mb-4">Monthly Payments</h2>

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
    </div>
    """
  end

  # Month Card Component
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
      "card border-2",
      @month_status == :paid && "border-success bg-success/5",
      @month_status == :partial && "border-warning bg-warning/5",
      @month_status == :unpaid && "border-base-300"
    ]}>
      <div class="card-body p-4">
        <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-3">
          <div>
            <h3 class="font-semibold text-lg">Month {@month}</h3>
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
          <div class="divider my-2"></div>
          <div class="space-y-2">
            <%= for payment <- @month_payments do %>
              <.payment_submission_item payment={payment} />
            <% end %>
          </div>
        <% end %>

        <%= if @can_submit do %>
          <div class="card-actions justify-end mt-3">
            <.link
              navigate={~p"/contracts/#{@contract.id}/payments/new?month=#{@month}"}
              class="btn btn-primary btn-sm"
            >
              <.icon name="hero-plus" class="w-4 h-4 mr-1" /> Submit Payment
            </.link>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Payment Submission Item Component
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
        <span class="text-error text-sm badge badge-error badge-outline">
          {@payment.rejection_reason}
        </span>
      <% end %>
    </div>
    """
  end

  # Payment History Section
  defp payment_history_section(assigns) do
    sorted_payments = Enum.sort_by(assigns.payments, & &1.inserted_at, :desc)

    assigns = assign(assigns, sorted_payments: sorted_payments)

    ~H"""
    <div class="card bg-base-100 shadow-lg">
      <div class="card-body">
        <h2 class="card-title text-xl mb-4">Payment History</h2>

        <%= if @sorted_payments != [] do %>
          <div class="overflow-x-auto">
            <table class="table table-zebra w-full">
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Month</th>
                  <th>Amount</th>
                  <th>Status</th>
                  <th>Notes</th>
                </tr>
              </thead>
              <tbody>
                <%= for payment <- @sorted_payments do %>
                  <tr>
                    <td>{format_datetime(payment.inserted_at)}</td>
                    <td>Month {payment.payment_number}</td>
                    <td class="font-medium">{format_currency(payment.amount)}</td>
                    <td><.payment_badge status={payment.status} /></td>
                    <td class="text-base-content/70 max-w-xs truncate">
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
    </div>
    """
  end

  # No Contract Message
  defp no_contract_message(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-lg">
      <div class="card-body text-center py-12">
        <.icon name="hero-home" class="w-16 h-16 mx-auto text-base-content/30 mb-4" />
        <h2 class="card-title text-xl justify-center mb-2">No Active Lease</h2>
        <p class="text-base-content/60">You don't have an active rental contract.</p>
      </div>
    </div>
    """
  end

  # Payment Status Badge (Contract Level)
  defp payment_status_badge(%{status: nil} = assigns) do
    ~H"""
    <span class="badge badge-ghost">No Contract</span>
    """
  end

  defp payment_status_badge(assigns) do
    colors = %{
      paid: "badge-success",
      on_time: "badge-info",
      overdue: "badge-error",
      upcoming: "badge-ghost"
    }

    labels = %{
      paid: "Paid Up",
      on_time: "On Time",
      overdue: "Overdue",
      upcoming: "Upcoming"
    }

    assigns =
      assign(assigns,
        color: Map.get(colors, assigns.status, "badge-ghost"),
        label: Map.get(labels, assigns.status, "Unknown")
      )

    ~H"""
    <span class={["badge badge-lg", @color]}>{@label}</span>
    """
  end

  # Month Status Badge
  defp month_status_badge(assigns) do
    colors = %{
      paid: "badge-success",
      partial: "badge-warning",
      unpaid: "badge-ghost"
    }

    labels = %{
      paid: "Paid",
      partial: "Partial",
      unpaid: "Unpaid"
    }

    assigns =
      assign(assigns,
        color: Map.get(colors, assigns.status, "badge-ghost"),
        label: Map.get(labels, assigns.status, "Unknown")
      )

    ~H"""
    <span class={["badge", @color]}>{@label}</span>
    """
  end

  # Payment Badge (Individual Payment Status)
  defp payment_badge(assigns) do
    colors = %{
      pending: "badge-warning",
      accepted: "badge-success",
      rejected: "badge-error"
    }

    labels = %{
      pending: "Pending",
      accepted: "Accepted",
      rejected: "Rejected"
    }

    assigns =
      assign(assigns,
        color: Map.get(colors, assigns.status, "badge-ghost"),
        label: Map.get(labels, assigns.status, "Unknown")
      )

    ~H"""
    <span class={["badge badge-sm", @color]}>{@label}</span>
    """
  end

  # Helper Functions
  defp format_date(date) do
    Calendar.strftime(date, "%b %d, %Y")
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %I:%M %p")
  end
end
