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
    # Extract payment info fields from the contract's property owner
    # Handle cases where contract, property, or user might be nil
    owner =
      if assigns.contract do
        assigns.contract.user
      end

    {visible_payment_fields, has_payment_info} =
      if owner do
        payment_fields = [
          {:cbu, owner.cbu, "CBU"},
          {:alias, owner.alias, "Alias"},
          {:account_name, owner.account_name, "Account Holder"}
        ]

        # Filter out fields with nil values
        visible = Enum.filter(payment_fields, fn {_key, value, _label} -> value != nil end)
        {visible, visible != []}
      else
        {[], false}
      end

    assigns =
      assigns
      |> assign(:visible_payment_fields, visible_payment_fields)
      |> assign(:has_payment_info, has_payment_info)

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

          <%!-- Payment Info Section - Owner's Bank Details --%>
          <%= if @has_payment_info do %>
            <.payment_info_card fields={@visible_payment_fields} />
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

  # Payment info card component - displays owner's bank details
  attr :fields, :list, required: true, doc: "List of {key, value, label} tuples for payment info"

  defp payment_info_card(assigns) do
    ~H"""
    <div class="mb-6">
      <%!-- Section Header --%>
      <div class="flex items-center gap-2 mb-3">
        <div class="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center">
          <.icon name="hero-banknotes" class="w-4 h-4 text-primary" />
        </div>
        <div>
          <h4 class="text-sm font-semibold text-base-content">Payment Information</h4>
          <p class="text-xs text-base-content/60">Transfer to this account</p>
        </div>
      </div>

      <%!-- Payment Details Card --%>
      <div class="bg-gradient-to-br from-base-100 to-base-200/50 border border-base-300 rounded-xl p-4 shadow-sm">
        <div class="space-y-3">
          <%= for {key, value, label} <- @fields do %>
            <div class="group">
              <label class="text-xs font-medium text-base-content/60 uppercase tracking-wide mb-1 block">
                {label}
              </label>
              <div class="flex items-center gap-2">
                <div
                  class="flex-1 bg-base-100 border border-base-300 rounded-lg px-3 py-2.5 text-sm font-mono text-base-content break-all select-all shadow-inner"
                  id={"payment-field-#{key}"}
                >
                  {value}
                </div>
                <button
                  type="button"
                  id={"copy-btn-#{key}"}
                  phx-hook=".CopyButton"
                  data-copy-target={"payment-field-#{key}"}
                  class="flex-shrink-0 btn btn-ghost btn-sm h-10 w-10 p-0 min-h-0 rounded-lg hover:bg-primary/10 hover:text-primary transition-colors"
                  aria-label={"Copy #{label}"}
                  title={"Copy #{label}"}
                >
                  <.icon name="hero-clipboard-document" class="w-4 h-4 copy-icon" />
                  <.icon name="hero-check" class="w-4 h-4 check-icon hidden" />
                </button>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- Helper hint --%>
        <div class="mt-4 flex items-start gap-2 text-xs text-base-content/60">
          <.icon name="hero-information-circle" class="w-4 h-4 flex-shrink-0 mt-0.5" />
          <p>Click the copy button next to any field to copy it to your clipboard</p>
        </div>
      </div>

      <%!-- Colocated Hook for Copy Functionality --%>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyButton">
        export default {
          mounted() {
            const targetId = this.el.dataset.copyTarget;
            const copyIcon = this.el.querySelector('.copy-icon');
            const checkIcon = this.el.querySelector('.check-icon');

            this.el.addEventListener('click', async () => {
              const targetElement = document.getElementById(targetId);
              if (!targetElement) return;

              const textToCopy = targetElement.textContent.trim();

              try {
                await navigator.clipboard.writeText(textToCopy);

                // Show success state
                copyIcon.classList.add('hidden');
                checkIcon.classList.remove('hidden');
                this.el.classList.add('text-success');

                // Reset after 2 seconds
                setTimeout(() => {
                  copyIcon.classList.remove('hidden');
                  checkIcon.classList.add('hidden');
                  this.el.classList.remove('text-success');
                }, 2000);
              } catch (err) {
                console.error('Failed to copy:', err);
              }
            });
          }
        }
      </script>
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
            send(self(), {:flash, :info, success_message(socket.assigns.type)})
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

  # Returns the appropriate success message based on payment type
  defp success_message(:rent), do: "Payment submitted successfully!"
  defp success_message(_type), do: "Miscellaneous payment submitted successfully!"
end
