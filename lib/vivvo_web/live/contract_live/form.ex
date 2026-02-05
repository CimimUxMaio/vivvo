defmodule VivvoWeb.ContractLive.Form do
  use VivvoWeb, :live_view

  alias Vivvo.Accounts
  alias Vivvo.Contracts
  alias Vivvo.Contracts.Contract
  alias Vivvo.Properties

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {if @live_action == :new, do: "New Contract for", else: "Edit Contract for"} {@property.name}
        <:actions>
          <.button navigate={~p"/properties/#{@property}"}>
            <.icon name="hero-arrow-left" /> Back
          </.button>
        </:actions>
      </.header>

      <%!-- Warning if replacing existing contract --%>
      <%= if @live_action == :new && @existing_contract do %>
        <div class="rounded-md bg-yellow-50 p-4 mb-6">
          <div class="flex">
            <div class="flex-shrink-0">
              <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-yellow-400" />
            </div>
            <div class="ml-3">
              <h3 class="text-sm font-medium text-yellow-800">
                Warning: Replacing existing contract
              </h3>
              <div class="mt-2 text-sm text-yellow-700">
                <p>
                  This will replace the current active contract for this property.
                  The existing contract will be archived.
                </p>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%= if @tenant_users == [] do %>
        <div class="rounded-md bg-red-50 p-4 mb-6">
          <div class="flex">
            <div class="flex-shrink-0">
              <.icon name="hero-x-circle" class="h-5 w-5 text-red-400" />
            </div>
            <div class="ml-3">
              <h3 class="text-sm font-medium text-red-800">
                No tenants available
              </h3>
              <div class="mt-2 text-sm text-red-700">
                <p>
                  No users with tenant role found. Please register tenants first before creating a contract.
                </p>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <.form for={@form} id="contract-form" phx-change="validate" phx-submit="save">
        <%!-- Hidden property_id field --%>
        <.input field={@form[:property_id]} type="hidden" value={@property.id} />

        <%!-- Property display (read-only) --%>
        <div class="mb-6 p-4 bg-gray-50 rounded-lg">
          <label class="block text-sm font-semibold leading-6 text-zinc-900 mb-2">
            Property
          </label>
          <p class="text-sm text-gray-700">
            {@property.name} - {@property.address}
          </p>
        </div>

        <%!-- Tenant select dropdown --%>
        <.input
          field={@form[:tenant_id]}
          type="select"
          label="Tenant"
          prompt="Select a tenant..."
          options={
            Enum.map(@tenant_users, fn user ->
              {"#{user.last_name}, #{user.first_name} (#{user.email})", user.id}
            end)
          }
          required
          disabled={@tenant_users == []}
        />

        <%!-- Date fields --%>
        <.input field={@form[:start_date]} type="date" label="Start Date" required />
        <.input field={@form[:end_date]} type="date" label="End Date" required />

        <%!-- Expiration day --%>
        <.input
          field={@form[:expiration_day]}
          type="number"
          label="Payment Due Day"
          placeholder="1-20"
          min="1"
          max="20"
          required
        />

        <%!-- Rent --%>
        <.input
          field={@form[:rent]}
          type="number"
          label="Monthly Rent"
          step="0.01"
          min="0.01"
          required
        />

        <%!-- Notes --%>
        <.input field={@form[:notes]} type="textarea" label="Notes (Optional)" />

        <%!-- Submit button --%>
        <footer>
          <.button
            variant="primary"
            type="submit"
            phx-disable-with="Saving..."
            disabled={@tenant_users == []}
          >
            {if @live_action == :new, do: "Create Contract", else: "Update Contract"}
          </.button>
          <.button navigate={~p"/properties/#{@property}"}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    property_id = params["property_id"]
    property = Properties.get_property!(socket.assigns.current_scope, property_id)
    tenant_users = Accounts.list_users_with_tenant_role(socket.assigns.current_scope)

    existing_contract =
      Contracts.get_contract_for_property(socket.assigns.current_scope, property.id)

    {:ok,
     socket
     |> assign(:property, property)
     |> assign(:tenant_users, tenant_users)
     |> assign(:existing_contract, existing_contract)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    contract = %Contract{}

    socket
    |> assign(:page_title, "New Contract")
    |> assign(:contract, contract)
    |> assign(:form, to_form(Contracts.change_contract(socket.assigns.current_scope, contract)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    contract = Contracts.get_contract!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Contract")
    |> assign(:contract, contract)
    |> assign(:form, to_form(Contracts.change_contract(socket.assigns.current_scope, contract)))
  end

  @impl true
  def handle_event("validate", %{"contract" => contract_params}, socket) do
    changeset =
      Contracts.change_contract(
        socket.assigns.current_scope,
        socket.assigns.contract,
        contract_params
      )

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"contract" => contract_params}, socket) do
    save_contract(socket, socket.assigns.live_action, contract_params)
  end

  defp save_contract(socket, :new, contract_params) do
    case Contracts.create_contract(socket.assigns.current_scope, contract_params) do
      {:ok, _contract} ->
        {:noreply,
         socket
         |> put_flash(:info, "Contract created successfully")
         |> push_navigate(to: ~p"/properties/#{socket.assigns.property}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_contract(socket, :edit, contract_params) do
    case Contracts.update_contract(
           socket.assigns.current_scope,
           socket.assigns.contract,
           contract_params
         ) do
      {:ok, _contract} ->
        {:noreply,
         socket
         |> put_flash(:info, "Contract updated successfully")
         |> push_navigate(to: ~p"/properties/#{socket.assigns.property}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
