defmodule VivvoWeb.RejectPaymentModal do
  @moduledoc """
  LiveComponent for rejecting payments with a reason.

  This LiveComponent manages all internal state including:
  - Form state and validation
  - Payment rejection logic

  Uses the generic modal component for responsive behavior:
  - Desktop: Centered floating modal
  - Mobile: Slides up from bottom with top corners rounded

  ## Attributes

    * `id` - Required. The DOM id for the component
    * `current_scope` - Required. The current user scope for permissions

  ## Example

      <.live_component
        module={VivvoWeb.RejectPaymentModal}
        id="reject-payment-modal"
        current_scope={@current_scope}
      />
  """
  use VivvoWeb, :live_component

  alias Vivvo.Payments

  @impl true
  def mount(socket) do
    {:ok, assign(socket, form: nil, payment: nil)}
  end

  @impl true
  def update(assigns, socket) do
    # Check if payment changed from current assigns
    payment_changed = assigns[:payment] != socket.assigns[:payment]

    socket = assign(socket, assigns)

    socket =
      if payment_changed do
        reset_form(socket)
      else
        socket
      end

    {:ok, socket}
  end

  # Reset form to its initial state based on current payment
  defp reset_form(%{assigns: %{payment: nil}} = socket) do
    assign(socket, form: nil)
  end

  defp reset_form(socket) do
    payment = socket.assigns.payment
    changeset = Payments.change_payment_validation(payment, %{"status" => "rejected"})

    assign(socket, form: to_form(changeset))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id <> "-wrapper"}>
      <%= if @form do %>
        <.modal id={@id}>
          <:header>
            <h3 class="card-title text-lg">Reject Payment</h3>
            <p class="text-base-content/70 mt-2">
              Please provide a reason for rejecting this payment.
            </p>
          </:header>

          <:body>
            <.form
              for={@form}
              id={@id <> "-form"}
              phx-submit="submit"
              phx-change="validate"
              phx-target={@myself}
            >
              <.input
                field={@form[:rejection_reason]}
                type="textarea"
                rows="3"
                placeholder="Enter rejection reason..."
                required
                label="Rejection Reason"
              />
            </.form>
          </:body>

          <:footer>
            <button
              type="button"
              phx-click={close_modal(@id)}
              phx-target={@myself}
              class="btn btn-ghost"
            >
              Cancel
            </button>
            <button
              type="submit"
              form={@id <> "-form"}
              class="btn btn-error"
              phx-disable-with="Rejecting..."
            >
              Reject Payment
            </button>
          </:footer>
        </.modal>
      <% end %>
    </div>
    """
  end

  # Event handlers

  @impl true
  def handle_event("validate", %{"payment" => params}, socket) do
    # Ensure status is set for validation (required by Payment.validation_changeset)
    params = Map.put(params, "status", "rejected")

    changeset =
      socket.assigns.payment
      |> Payments.change_payment_validation(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("submit", %{"payment" => params}, socket) do
    payment = socket.assigns.payment
    reason = params["rejection_reason"]

    case Payments.reject_payment(socket.assigns.current_scope, payment, reason) do
      {:ok, _payment} ->
        send(self(), {:flash, :info, "Payment rejected"})
        {:noreply, push_modal_close(socket, socket.assigns.id)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, :unauthorized} ->
        send(self(), {:flash, :error, "You are not authorized to reject this payment"})
        {:noreply, push_modal_close(socket, socket.assigns.id)}
    end
  end
end
