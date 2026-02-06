defmodule VivvoWeb.PropertyLive.Show do
  use VivvoWeb, :live_view

  alias Vivvo.Contracts
  alias Vivvo.Payments
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

      <%!-- CONTRACT PAYMENTS SECTION --%>
      <%= if @contract do %>
        <.contract_payments_section
          contract={@contract}
          months={@months}
          scope={@current_scope}
        />
      <% end %>

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

      <%!-- REJECT MODAL --%>
      <%= if @rejecting_payment do %>
        <.reject_modal payment={@rejecting_payment} />
      <% end %>
    </Layouts.app>
    """
  end

  # Contract Payments Section Component
  defp contract_payments_section(assigns) do
    ~H"""
    <div class="mt-8">
      <.header>
        Contract Payments
        <:subtitle>Manage monthly payments and submissions</:subtitle>
      </.header>

      <div class="space-y-4 mt-4">
        <%= for month <- @months do %>
          <.owner_month_card
            contract={@contract}
            month={month}
            payments={get_payments_for_month(@contract.payments, month)}
            scope={@scope}
          />
        <% end %>
      </div>
    </div>
    """
  end

  # Owner Month Card Component
  defp owner_month_card(assigns) do
    scope = assigns.scope
    contract = assigns.contract
    month = assigns.month

    total_paid = Payments.total_accepted_for_month(scope, contract.id, month)
    due_date = Contracts.calculate_due_date(contract, month)

    rent_decimal = Decimal.new(to_string(contract.rent))

    progress_pct =
      if Decimal.compare(rent_decimal, Decimal.new(0)) == :gt do
        total_paid
        |> Decimal.div(rent_decimal)
        |> Decimal.mult(100)
        |> Decimal.round(0)
        |> Decimal.to_integer()
        |> min(100)
      else
        0
      end

    month_status = Payments.get_month_status(scope, contract, month)

    assigns =
      assign(assigns,
        total_paid: total_paid,
        due_date: due_date,
        progress_pct: progress_pct,
        month_status: month_status
      )

    ~H"""
    <div class={[
      "card bg-base-100 shadow-md border-l-4",
      month_status_border(@month_status)
    ]}>
      <div class="card-body p-4">
        <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-2 mb-3">
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
          </div>
        </div>

        <%!-- Progress Bar --%>
        <div class="w-full bg-base-300 rounded-full h-2 mb-3">
          <div
            class="bg-primary h-2 rounded-full transition-all duration-300"
            style={"width: #{@progress_pct}%"}
          >
          </div>
        </div>

        <%!-- Payment Submissions --%>
        <%= if @payments != [] do %>
          <div class="divider my-2"></div>
          <div class="space-y-2">
            <%= for payment <- @payments do %>
              <.owner_payment_item payment={payment} />
            <% end %>
          </div>
        <% else %>
          <p class="text-sm text-base-content/60 italic">No payments submitted for this month.</p>
        <% end %>
      </div>
    </div>
    """
  end

  # Owner Payment Item Component
  defp owner_payment_item(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 p-3 bg-base-200 rounded-lg">
      <div class="flex flex-wrap items-center gap-3">
        <.payment_badge status={@payment.status} />
        <span class="font-medium">{format_currency(@payment.amount)}</span>
        <%= if @payment.notes && @payment.notes != "" do %>
          <span class="text-sm text-base-content/60">- {@payment.notes}</span>
        <% end %>
      </div>

      <%= if @payment.status == :pending do %>
        <div class="flex gap-2">
          <button
            phx-click="accept-payment"
            phx-value-payment-id={@payment.id}
            class="btn btn-success btn-sm"
          >
            <.icon name="hero-check" class="w-4 h-4 mr-1" /> Accept
          </button>
          <button
            phx-click="show-reject-modal"
            phx-value-payment-id={@payment.id}
            class="btn btn-error btn-sm"
          >
            <.icon name="hero-x-mark" class="w-4 h-4 mr-1" /> Reject
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  # Reject Modal Component
  defp reject_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div class="card bg-base-100 w-full max-w-md shadow-2xl">
        <div class="card-body">
          <h3 class="card-title text-lg">Reject Payment</h3>
          <p class="text-base-content/70 mb-4">
            Please provide a reason for rejecting this payment.
          </p>

          <form phx-submit="reject-payment" id="reject-form">
            <.input
              type="textarea"
              name="rejection-reason"
              rows="3"
              placeholder="Enter rejection reason..."
              required
              label="Rejection Reason"
            />

            <div class="card-actions justify-end gap-3 mt-4">
              <button
                type="button"
                phx-click="close-reject-modal"
                class="btn btn-ghost"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="btn btn-error"
                phx-disable-with="Rejecting..."
              >
                Reject Payment
              </button>
            </div>
          </form>
        </div>
      </div>
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

    scope = socket.assigns.current_scope
    property = Properties.get_property!(scope, id)
    contract = Contracts.get_contract_for_property(scope, property.id)

    months = if contract, do: Contracts.get_months_up_to_current(contract), else: []

    {:ok,
     socket
     |> assign(:page_title, "Show Property")
     |> assign(:property, property)
     |> assign(:contract, contract)
     |> assign(:months, months)
     |> assign(:show_contract_modal, false)
     |> assign(:rejecting_payment, nil)}
  end

  @impl true
  def handle_event("show_contract_modal", _params, socket) do
    {:noreply, assign(socket, :show_contract_modal, true)}
  end

  @impl true
  def handle_event("accept-payment", %{"payment-id" => payment_id}, socket) do
    scope = socket.assigns.current_scope

    case Payments.get_payment(scope, payment_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Payment not found")}

      payment ->
        case Payments.accept_payment(scope, payment) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Payment accepted successfully")
             |> refresh_contract_data()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to accept payment")}
        end
    end
  end

  @impl true
  def handle_event("show-reject-modal", %{"payment-id" => payment_id}, socket) do
    scope = socket.assigns.current_scope

    case Payments.get_payment(scope, payment_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Payment not found")}

      payment ->
        {:noreply, assign(socket, :rejecting_payment, payment)}
    end
  end

  @impl true
  def handle_event("reject-payment", %{"rejection-reason" => reason}, socket) do
    scope = socket.assigns.current_scope
    payment = socket.assigns.rejecting_payment

    case Payments.reject_payment(scope, payment, reason) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:rejecting_payment, nil)
         |> put_flash(:info, "Payment rejected successfully")
         |> refresh_contract_data()}

      {:error, changeset} ->
        errors = format_changeset_errors(changeset)
        {:noreply, put_flash(socket, :error, "Failed to reject payment: #{errors}")}
    end
  end

  @impl true
  def handle_event("close-reject-modal", _params, socket) do
    {:noreply, assign(socket, :rejecting_payment, nil)}
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
    contract = Vivvo.Repo.preload(contract, [:tenant, :payments])

    months = Contracts.get_months_up_to_current(contract)

    {:noreply,
     socket
     |> assign(:contract, contract)
     |> assign(:months, months)}
  end

  def handle_info(
        {:updated, %Vivvo.Contracts.Contract{property_id: property_id} = contract},
        socket
      )
      when property_id == socket.assigns.property.id do
    contract = Vivvo.Repo.preload(contract, [:tenant, :payments])

    months = Contracts.get_months_up_to_current(contract)

    {:noreply,
     socket
     |> assign(:contract, contract)
     |> assign(:months, months)}
  end

  def handle_info({:deleted, %Vivvo.Contracts.Contract{property_id: property_id}}, socket)
      when property_id == socket.assigns.property.id do
    {:noreply,
     socket
     |> assign(:contract, nil)
     |> assign(:months, [])}
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

  # Handle payment events
  def handle_info({_action, %Vivvo.Payments.Payment{contract_id: contract_id}}, socket)
      when contract_id == socket.assigns.contract.id do
    {:noreply, refresh_contract_data(socket)}
  end

  def handle_info({_action, %Vivvo.Payments.Payment{}}, socket) do
    {:noreply, socket}
  end

  # Component Functions

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

  defp refresh_contract_data(socket) do
    scope = socket.assigns.current_scope
    contract = Contracts.get_contract_for_property(scope, socket.assigns.property.id)

    if contract do
      contract = Vivvo.Repo.preload(contract, [:tenant, :payments])
      months = Contracts.get_months_up_to_current(contract)

      socket
      |> assign(:contract, contract)
      |> assign(:months, months)
    else
      assign(socket, :contract, nil)
    end
  end

  defp get_payments_for_month(payments, month) do
    Enum.filter(payments, &(&1.payment_number == month))
  end

  defp month_status_border(:paid), do: "border-success"
  defp month_status_border(:partial), do: "border-warning"
  defp month_status_border(:unpaid), do: "border-base-300"
  defp month_status_border(_), do: "border-base-300"

  defp format_date(date) do
    Calendar.strftime(date, "%b %d, %Y")
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join("; ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
