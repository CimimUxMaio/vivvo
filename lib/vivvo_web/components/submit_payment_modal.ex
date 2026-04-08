defmodule VivvoWeb.SubmitPaymentModal do
  @moduledoc """
  Modal component for submitting payments with file upload support.
  Features fixed height with scrollable content.
  Supports both rent payments (with progress tracking) and miscellaneous payments.
  """
  use Phoenix.Component

  import VivvoWeb.CoreComponents, only: [input: 1, icon: 1]
  import VivvoWeb.FormatHelpers, only: [format_currency: 1]
  alias VivvoWeb.FileUploadComponent

  attr :id, :string, required: true
  attr :form, :map, required: true
  attr :uploads, :map, required: true
  attr :submitting_payment, :any, required: true, doc: "{contract, month | nil, type}"

  attr :payment_summary, :map,
    default: nil,
    doc: "Summary with rent, accepted_total, pending_total, remaining"

  attr :submit_event, :string, required: true
  attr :close_event, :string, required: true
  attr :validation_event, :string, default: "validate_payment"

  def submit_payment_modal(assigns) do
    {contract, month, type} = assigns.submitting_payment
    is_rent = type == :rent

    assigns =
      if is_rent and assigns.payment_summary do
        summary = assigns.payment_summary
        rent = summary[:rent]
        accepted_total = summary[:accepted_total]
        pending_total = summary[:pending_total]
        remaining = summary[:remaining]

        accepted_pct = calculate_progress_percentage(accepted_total, rent)
        pending_pct = calculate_progress_percentage(pending_total, rent)
        total_pct = min(accepted_pct + pending_pct, 100.0)
        is_over_limit = Decimal.lt?(remaining, Decimal.new(0))

        assign(assigns,
          contract: contract,
          month: month,
          type: type,
          is_rent: true,
          rent: rent,
          accepted_total: accepted_total,
          pending_total: pending_total,
          remaining: remaining,
          accepted_pct: accepted_pct,
          pending_pct: pending_pct,
          total_pct: total_pct,
          is_over_limit: is_over_limit
        )
      else
        assign(assigns,
          contract: contract,
          month: month,
          type: type,
          is_rent: false,
          is_over_limit: false
        )
      end

    ~H"""
    <div id={@id} class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <%!-- Fixed max height with scrollable content --%>
      <div class="card bg-base-100 w-full max-w-lg max-h-[90vh] shadow-2xl flex flex-col">
        <%!-- Header - Fixed --%>
        <div class="p-6 border-b border-base-200 flex-shrink-0">
          <%= if @is_rent do %>
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
        </div>

        <%!-- Scrollable Content --%>
        <div class="overflow-y-auto flex-1 p-6">
          <%= if @is_rent do %>
            <%!-- Payment Progress Bar (only for rent payments) --%>
            <div class="mb-6 p-4 bg-base-200/50 rounded-lg">
              <div class="flex justify-between items-center mb-2">
                <span class="text-sm font-medium">Monthly Rent</span>
                <span class="text-lg font-bold">{format_currency(@rent)}</span>
              </div>

              <%!-- Progress bar with stacked segments --%>
              <div class="h-4 bg-base-300 rounded-full overflow-hidden flex">
                <div
                  class="h-full bg-success transition-all duration-300"
                  style={"width: #{@accepted_pct}%"}
                  title={"Accepted: #{format_currency(@accepted_total)}"}
                >
                </div>
                <div
                  class="h-full bg-warning transition-all duration-300"
                  style={"width: #{@pending_pct}%"}
                  title={"Pending: #{format_currency(@pending_total)}"}
                >
                </div>
              </div>

              <div class="flex justify-between text-xs mt-2 text-base-content/70">
                <span>{Float.round(@total_pct, 2)}% covered</span>
                <span class={[
                  Decimal.lte?(@remaining, Decimal.new(0)) && "text-error font-medium"
                ]}>
                  Remaining: {format_currency(@remaining)}
                </span>
              </div>

              <%!-- Legend --%>
              <div class="flex gap-4 mt-3 text-xs">
                <div class="flex items-center gap-1.5">
                  <div class="w-3 h-3 rounded bg-success"></div>
                  <span>Paid: {format_currency(@accepted_total)}</span>
                </div>
                <div class="flex items-center gap-1.5">
                  <div class="w-3 h-3 rounded bg-warning"></div>
                  <span>Pending: {format_currency(@pending_total)}</span>
                </div>
              </div>
            </div>
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
            phx-submit={@submit_event}
            phx-change={@validation_event}
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

              <%= if not @is_rent do %>
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

              <%!-- File Upload Section using reusable component --%>
              <.live_component
                module={FileUploadComponent}
                id={@id <> "-files"}
                upload={@uploads.files}
                field={@form[:files]}
                label="Supporting Documents (Optional)"
              />

              <.input field={@form[:contract_id]} type="hidden" value={@contract.id} />
              <.input field={@form[:type]} type="hidden" value={@type} />
              <%= if @is_rent do %>
                <.input field={@form[:payment_number]} type="hidden" value={@month} />
              <% end %>
            </div>
          </.form>
        </div>

        <%!-- Footer - Fixed --%>
        <div class="p-6 border-t border-base-200 flex-shrink-0">
          <div class="card-actions justify-end gap-3">
            <button
              type="button"
              phx-click={@close_event}
              class="btn btn-ghost"
            >
              Cancel
            </button>
            <button
              type="submit"
              form={@id <> "-form"}
              class={[
                "btn btn-primary",
                @is_over_limit && "btn-disabled opacity-50 cursor-not-allowed"
              ]}
              disabled={@is_over_limit}
              phx-disable-with="Submitting..."
            >
              <%= if @is_rent do %>
                Submit Payment
              <% else %>
                Submit Miscellaneous Payment
              <% end %>
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_due_date(contract, month) do
    due_date = Vivvo.Contracts.calculate_due_date(contract, month)
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
    Vivvo.Payments.Payment
    |> Ecto.Enum.values(:category)
    |> Enum.map(fn cat ->
      label =
        cat
        |> Atom.to_string()
        |> String.capitalize()

      {label, cat}
    end)
  end
end
