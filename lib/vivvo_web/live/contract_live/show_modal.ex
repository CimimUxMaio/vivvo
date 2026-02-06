defmodule VivvoWeb.ContractLive.ShowModal do
  use VivvoWeb, :live_component

  alias Vivvo.Contracts

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto"
      phx-remove={hide_modal()}
    >
      <%!-- Backdrop --%>
      <div
        class="fixed inset-0 bg-black/50 transition-opacity"
        phx-click={JS.push("close_modal", target: @myself)}
      >
      </div>

      <%!-- Modal content --%>
      <div class="relative z-50 w-full max-w-3xl mx-4 my-8">
        <div class="bg-white rounded-lg shadow-xl">
          <%!-- Header --%>
          <div class="flex items-center justify-between p-6 border-b border-gray-200">
            <h2 class="text-xl font-semibold text-gray-900">Contract Details</h2>
            <button
              type="button"
              phx-click={JS.push("close_modal", target: @myself)}
              class="text-gray-400 hover:text-gray-500"
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="h-6 w-6" />
            </button>
          </div>

          <%!-- Body --%>
          <div class="p-6">
            <.list>
              <%!-- Property Info --%>
              <:item title="Property">
                {@property.name} - {@property.address}
              </:item>

              <%!-- Tenant Info --%>
              <:item title="Tenant">
                {@contract.tenant.first_name} {@contract.tenant.last_name}
              </:item>
              <:item title="Tenant Email">{@contract.tenant.email}</:item>
              <:item :if={@contract.tenant.phone_number} title="Tenant Phone">
                {@contract.tenant.phone_number}
              </:item>

              <%!-- Contract Dates --%>
              <:item title="Start Date">{Calendar.strftime(@contract.start_date, "%B %d, %Y")}</:item>
              <:item title="End Date">{Calendar.strftime(@contract.end_date, "%B %d, %Y")}</:item>

              <%!-- Contract Status --%>
              <:item title="Status">
                <.contract_status_badge status={contract_status(@contract)} />
              </:item>

              <%!-- Payment Info --%>
              <:item title="Payment Due Day">Day {@contract.expiration_day} of each month</:item>
              <:item title="Monthly Rent">{format_currency(@contract.rent)}</:item>

              <%!-- Notes --%>
              <:item :if={@contract.notes && @contract.notes != ""} title="Notes">
                {@contract.notes}
              </:item>
            </.list>
          </div>

          <%!-- Footer --%>
          <div class="flex items-center justify-end gap-3 p-6 border-t border-gray-200">
            <.button navigate={~p"/properties/#{@property}/contracts/#{@contract}/edit"}>
              <.icon name="hero-pencil-square" /> Edit
            </.button>
            <.button
              phx-click="archive"
              phx-target={@myself}
              data-confirm="Are you sure you want to archive this contract? The property will no longer have an active contract."
              class="btn btn-error"
            >
              <.icon name="hero-archive-box" /> Archive
            </.button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    send(self(), :close_contract_modal)
    {:noreply, socket}
  end

  def handle_event("archive", _params, socket) do
    contract = socket.assigns.contract
    {:ok, _} = Contracts.delete_contract(socket.assigns.current_scope, contract)

    send(self(), :close_contract_modal)
    {:noreply, socket}
  end

  defp contract_status(contract) do
    Contracts.contract_status(contract)
  end

  defp hide_modal(js \\ %JS{}) do
    js
    |> JS.hide(
      to: "#contract-modal",
      transition: {"ease-in duration-200", "opacity-100", "opacity-0"}
    )
  end
end
