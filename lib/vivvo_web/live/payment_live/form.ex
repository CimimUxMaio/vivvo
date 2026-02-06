defmodule VivvoWeb.PaymentLive.Form do
  use VivvoWeb, :live_view

  alias Vivvo.Contracts
  alias Vivvo.Payments
  alias Vivvo.Payments.Payment

  @impl true
  def mount(%{"contract_id" => contract_id, "month" => month}, _session, socket) do
    scope = socket.assigns.current_scope

    # Verify user is a tenant
    if scope.user.current_role != :tenant do
      {:ok,
       socket
       |> put_flash(:error, "Only tenants can submit payments")
       |> push_navigate(to: ~p"/")}
    else
      # Parse month parameter safely
      case Integer.parse(month) do
        {month_num, _} when month_num > 0 ->
          mount_with_month(socket, scope, contract_id, month_num)

        _ ->
          {:ok,
           socket
           |> put_flash(:error, "Invalid month")
           |> push_navigate(to: ~p"/")}
      end
    end
  end

  defp mount_with_month(socket, scope, contract_id, month_num) do
    # Get contract and verify tenant owns it
    contract = Contracts.get_contract_for_tenant(scope, contract_id)

    if is_nil(contract) do
      {:ok,
       socket
       |> put_flash(:error, "Contract not found")
       |> push_navigate(to: ~p"/")}
    else
      changeset = Payments.change_payment(scope, %Payment{}, %{})

      socket =
        socket
        |> assign(:contract, contract)
        |> assign(:month, month_num)
        |> assign(:form, to_form(changeset))
        |> assign(:page_title, "Submit Payment")

      {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-lg mx-auto">
        <.link
          navigate={~p"/"}
          class="btn btn-ghost btn-sm mb-4"
        >
          <.icon name="hero-arrow-left" class="w-4 h-4 mr-1" /> Back to Home
        </.link>

        <div class="card bg-base-100 shadow-lg">
          <div class="card-body">
            <h1 class="card-title text-2xl mb-2">Submit Payment</h1>
            <p class="text-base-content/70 mb-6">
              Month {@month} - Due: {format_due_date(@contract, @month)}
            </p>

            <.form for={@form} id="payment-form" phx-submit="save" phx-change="validate">
              <div class="space-y-4">
                <.input
                  field={@form[:amount]}
                  type="number"
                  label="Amount ($)"
                  step="0.01"
                  min="0.01"
                  placeholder="Enter payment amount"
                  required
                />

                <.input
                  field={@form[:notes]}
                  type="textarea"
                  label="Notes (Optional)"
                  rows="3"
                  placeholder="Add any notes about this payment..."
                />

                <.input field={@form[:contract_id]} type="hidden" value={@contract.id} />
                <.input field={@form[:payment_number]} type="hidden" value={@month} />

                <div class="card-actions justify-end gap-3 pt-4">
                  <.link
                    navigate={~p"/"}
                    class="btn btn-ghost"
                  >
                    Cancel
                  </.link>
                  <.button
                    type="submit"
                    class="btn btn-primary"
                    phx-disable-with="Submitting..."
                  >
                    Submit Payment
                  </.button>
                </div>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"payment" => params}, socket) do
    scope = socket.assigns.current_scope

    changeset =
      Payments.change_payment(scope, %Payment{}, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"payment" => params}, socket) do
    scope = socket.assigns.current_scope

    attrs =
      params
      |> Map.put("contract_id", socket.assigns.contract.id)
      |> Map.put("payment_number", socket.assigns.month)

    case Payments.create_payment(scope, attrs) do
      {:ok, _payment} ->
        {:noreply,
         socket
         |> put_flash(:info, "Payment submitted successfully!")
         |> push_navigate(to: ~p"/")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # Helper function
  defp format_due_date(contract, month) do
    due_date = Contracts.calculate_due_date(contract, month)
    Calendar.strftime(due_date, "%b %d, %Y")
  end
end
