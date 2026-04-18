defmodule VivvoWeb.SubmitPaymentModal do
  @moduledoc """
  LiveComponent for submitting payments with file upload support.

  This LiveComponent manages all internal state including:
  - Form state and validation
  - File uploads
  - Payment calculations

  Uses the generic modal component for responsive behavior:
  - Desktop: Centered floating modal
  - Mobile: Slides up from bottom with top corners rounded

  Supports both rent payments (with progress tracking) and miscellaneous payments.

  ## Attributes

    * `id` - Required. The DOM id for the component
    * `contract` - Required. The contract map
    * `type` - Required. `:rent` or `:miscellaneous`
    * `month` - Optional. Payment month for rent (nil for miscellaneous)
    * `current_scope` - Required. The current user scope for permissions

  ## Example

      <.live_component
        module={VivvoWeb.SubmitPaymentModal}
        id="payment-modal"
        contract={@contract}
        type={:rent}
        month={1}
        current_scope={@current_scope}
      />
  """
  use VivvoWeb, :live_component

  alias Vivvo.Contracts
  alias Vivvo.Payments
  alias Vivvo.Payments.Payment

  # File upload configuration
  @file_config Application.compile_env(:vivvo, Vivvo.Files)

  @impl true
  def mount(socket) do
    socket =
      socket
      |> allow_upload(:files,
        accept: Enum.map(@file_config[:allowed_extensions], &".#{&1}"),
        max_entries: @file_config[:max_files_per_payment],
        max_file_size: @file_config[:max_file_size]
      )

    {:ok, assign(socket, form: nil)}
  end

  @impl true
  def update(assigns, socket) do
    # Check if key attributes changed from current assigns
    contract_changed = assigns.contract != socket.assigns[:contract]
    type_changed = assigns.type != socket.assigns[:type]
    month_changed = assigns.month != socket.assigns[:month]
    should_reset = contract_changed or type_changed or month_changed

    socket = assign(socket, assigns)

    socket =
      if should_reset do
        reset_form(socket)
      else
        socket
      end

    {:ok, socket}
  end

  # Reset form to its initial state based on current contract/type/month
  defp reset_form(%{assigns: %{contract: nil}} = socket) do
    assign(socket, form: nil)
  end

  defp reset_form(socket) do
    type = socket.assigns.type
    month = socket.assigns.month
    contract = socket.assigns.contract

    attrs = initial_attrs(type, contract, month)
    changeset = payment_changeset(socket, attrs)

    # Also cancel any pending uploads
    socket = cancel_uploads(socket)

    assign(socket,
      form: to_form(changeset),
      disabled: over_limit?(type, contract, month)
    )
  end

  defp cancel_uploads(socket) do
    # Cancel any pending uploads
    Enum.reduce(socket.assigns.uploads.files.entries, socket, fn entry, acc ->
      cancel_upload(acc, :files, entry.ref)
    end)
  end

  defp initial_attrs(:rent, contract, month) do
    summary = calculate_payment_summary(contract, month)
    initial_amount = Decimal.to_string(Decimal.min(summary.rent, summary.remaining))

    %{
      "amount" => initial_amount,
      "type" => "rent",
      "payment_number" => month
    }
  end

  defp initial_attrs(:miscellaneous, _contract, _month) do
    %{"amount" => "", "type" => "miscellaneous"}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id <> "-wrapper"}>
      <%= if @form do %>
        <.modal id={@id}>
          <:header>
            <%= if @type == :rent do %>
              <h3 class="card-title text-xl mb-2">Submit Payment</h3>
              <p class="text-base-content/70">
                Month {@month} - Due: {format_due_date(@contract, @month)}
              </p>
            <% else %>
              <h3 class="card-title text-xl mb-2">Submit Miscellaneous Payment</h3>
              <p class="text-base-content/70">
                {@contract.property.name}
              </p>
            <% end %>
          </:header>

          <%= if @type == :rent do %>
            <.payment_progress_bar contract={@contract} month={@month} />
          <% else %>
            <%!-- Miscellaneous payment info --%>
            <div class="mb-4 p-3 bg-warning/10 border border-warning/20 rounded-box flex items-start gap-3">
              <.icon name="hero-light-bulb" class="w-5 h-5 text-warning flex-shrink-0 mt-0.5" />
              <p class="text-sm text-base-content/80">
                This is an additional payment that will not count toward your rent totals. Use this for security deposits, pet fees, or other charges.
              </p>
            </div>
          <% end %>

          <.form
            for={@form}
            id={@id <> "-form"}
            phx-submit="submit"
            phx-change="validate"
            phx-target={@myself}
          >
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

              <%= if @type != :rent do %>
                <.input
                  field={@form[:category]}
                  type="select"
                  label="Category"
                  options={category_options()}
                  prompt="Select a category"
                  required
                />
              <% end %>

              <.input
                field={@form[:notes]}
                type="textarea"
                label="Notes (Optional)"
                rows="3"
                placeholder="Add any notes about this payment..."
              />

              <%!-- File Upload - managed internally --%>
              <.file_upload
                upload={@uploads.files}
                field={@form[:files]}
                label="Supporting Documents (Optional)"
                phx_target={@myself}
              />

              <.input field={@form[:contract_id]} type="hidden" value={@contract.id} />
              <.input field={@form[:type]} type="hidden" value={@type} />
              <%= if @type == :rent do %>
                <.input field={@form[:payment_number]} type="hidden" value={@month} />
              <% end %>
            </div>
          </.form>

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
              class={[
                "btn btn-primary",
                @disabled && "btn-disabled opacity-50 cursor-not-allowed"
              ]}
              disabled={@disabled}
              phx-disable-with="Submitting..."
            >
              Submit Payment
            </button>
          </:footer>
        </.modal>
      <% end %>
    </div>
    """
  end

  # Payment progress bar component
  attr :contract, :any, required: true
  attr :month, :any, required: true

  defp payment_progress_bar(assigns) do
    summary = calculate_payment_summary(assigns.contract, assigns.month)
    assigns = assign(assigns, :summary, summary)

    ~H"""
    <div class="mb-6 p-4 bg-base-200/50 rounded-lg">
      <div class="flex justify-between items-center mb-2">
        <span class="text-sm font-medium">Monthly Rent</span>
        <span class="text-lg font-bold">{format_currency(@summary.rent)}</span>
      </div>

      <div class="h-4 bg-base-300 rounded-full overflow-hidden flex">
        <div
          class="h-full bg-success transition-all duration-300"
          style={"width: #{calculate_progress_percentage(@summary.accepted_total, @summary.rent)}%"}
        >
        </div>
        <div
          class="h-full bg-warning transition-all duration-300"
          style={"width: #{calculate_progress_percentage(@summary.pending_total, @summary.rent)}%"}
        >
        </div>
      </div>

      <div class="flex justify-between text-xs mt-2 text-base-content/70">
        <span>
          {Float.round(
            calculate_progress_percentage(@summary.accepted_total, @summary.rent) +
              calculate_progress_percentage(@summary.pending_total, @summary.rent),
            2
          )}% covered
        </span>
        <span class={[
          Decimal.lte?(@summary.remaining, Decimal.new(0)) && "text-error font-medium"
        ]}>
          Remaining: {format_currency(@summary.remaining)}
        </span>
      </div>

      <div class="flex gap-4 mt-3 text-xs">
        <div class="flex items-center gap-1.5">
          <div class="w-3 h-3 rounded bg-success"></div>
          <span>Paid: {format_currency(@summary.accepted_total)}</span>
        </div>
        <div class="flex items-center gap-1.5">
          <div class="w-3 h-3 rounded bg-warning"></div>
          <span>Pending: {format_currency(@summary.pending_total)}</span>
        </div>
      </div>
    </div>
    """
  end

  # Event handlers

  @impl true
  def handle_event("validate", %{"payment" => params}, socket) do
    changeset =
      socket
      |> payment_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("submit", %{"payment" => params}, socket) do
    attrs =
      params
      |> Map.put("contract_id", socket.assigns.contract.id)
      |> then(&normalize_params(&1, socket.assigns.type, socket.assigns.month))

    opts = payment_opts(socket)

    socket =
      with_consumed_uploads(socket, :files, [], fn uploaded_files ->
        case Payments.create_payment(socket.assigns.current_scope, attrs, uploaded_files, opts) do
          {:ok, _payment} ->
            message =
              if socket.assigns.type == :rent,
                do: "Payment submitted successfully!",
                else: "Miscellaneous payment submitted successfully!"

            send(self(), {:flash, :info, message})
            push_modal_close(socket, socket.assigns.id)

          {:error, :contract_needs_update} ->
            send(
              self(),
              {:flash, :info, "Contract rent is being updated. Please try again shortly."}
            )

            socket

          {:error, %Ecto.Changeset{} = changeset} ->
            assign(socket, form: to_form(changeset))
        end
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  # Helper functions

  # Builds a changeset for payment validation from socket assigns and params
  defp payment_changeset(socket, params) do
    attrs = normalize_params(params, socket.assigns.type, socket.assigns.month)
    opts = payment_opts(socket)
    Payments.change_payment(socket.assigns.current_scope, %Payment{}, attrs, opts)
  end

  # Builds payment options (remaining_allowance for rent payments)
  defp payment_opts(%{assigns: %{type: :rent, contract: contract, month: month}}) do
    summary = calculate_payment_summary(contract, month)
    [remaining_allowance: summary.remaining]
  end

  defp payment_opts(%{assigns: %{type: :miscellaneous}}), do: []

  defp normalize_params(params, type, month) do
    params
    |> Map.put("type", to_string(type))
    |> Map.put("payment_number", if(type == :rent, do: month))
  end

  defp over_limit?(type, contract, month) do
    if type == :rent do
      summary = calculate_payment_summary(contract, month)
      Decimal.lt?(summary.remaining, Decimal.new(0))
    else
      false
    end
  end

  defp format_due_date(contract, month) do
    due_date = Contracts.calculate_due_date(contract, month)
    Calendar.strftime(due_date, "%b %d, %Y")
  end

  defp calculate_progress_percentage(amount, total) do
    if Decimal.gt?(total, Decimal.new(0)) do
      amount
      |> Decimal.div(total)
      |> Decimal.mult(Decimal.new(100))
      |> Decimal.to_float()
      |> Float.round(2)
      |> min(100.0)
    else
      0.0
    end
  end

  defp category_options do
    Payment
    |> Ecto.Enum.values(:category)
    |> Enum.map(fn cat ->
      label =
        cat
        |> Atom.to_string()
        |> String.capitalize()

      {label, cat}
    end)
  end

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

  defp calculate_payment_summary(contract, month) do
    {accepted_total, pending_total} = calculate_payment_totals(contract, month)
    due_date = Contracts.calculate_due_date(contract, month)
    rent = Contracts.latest_rent_value(contract, due_date)
    remaining = Decimal.sub(rent, Decimal.add(accepted_total, pending_total))

    %{
      rent: rent,
      accepted_total: accepted_total,
      pending_total: pending_total,
      remaining: remaining,
      due_date: due_date
    }
  end
end
