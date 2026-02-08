defmodule Vivvo.Contracts do
  @moduledoc """
  The Contracts context.
  """

  import Ecto.Query, warn: false
  alias Vivvo.Repo

  alias Vivvo.Accounts.Scope
  alias Vivvo.Contracts.Contract

  @doc """
  Subscribes to scoped notifications about any contract changes.

  The broadcasted messages match the pattern:

    * {:created, %Contract{}}
    * {:updated, %Contract{}}
    * {:deleted, %Contract{}}

  """
  def subscribe_contracts(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(Vivvo.PubSub, "user:#{key}:contracts")
  end

  defp broadcast_contract(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(Vivvo.PubSub, "user:#{key}:contracts", message)
  end

  @doc """
  Returns the list of contracts.

  ## Examples

      iex> list_contracts(scope)
      [%Contract{}, ...]

  """
  def list_contracts(%Scope{} = scope) do
    Repo.all_by(Contract, user_id: scope.user.id, archived: false)
  end

  @doc """
  Gets a single contract.

  Raises `Ecto.NoResultsError` if the Contract does not exist.

  ## Examples

      iex> get_contract!(scope, 123)
      %Contract{}

      iex> get_contract!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_contract!(%Scope{} = scope, id) do
    Repo.get_by!(Contract, id: id, user_id: scope.user.id, archived: false)
  end

  @doc """
  Gets the active contract for a specific property.

  Returns nil if no active contract exists, or the contract struct with tenant preloaded.

  ## Examples

      iex> get_contract_for_property(scope, 123)
      %Contract{tenant: %User{}}

      iex> get_contract_for_property(scope, 456)
      nil
  """
  def get_contract_for_property(%Scope{} = scope, property_id) do
    from(c in Contract,
      where:
        c.property_id == ^property_id and c.user_id == ^scope.user.id and c.archived == false,
      preload: [:tenant, :payments]
    )
    |> Repo.one()
  end

  @doc """
  Creates a contract.

  ## Examples

      iex> create_contract(scope, %{field: value})
      {:ok, %Contract{}}

      iex> create_contract(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_contract(%Scope{} = scope, attrs) do
    property_id = get_property_id(attrs)
    old_contract = maybe_get_contract_for_property(scope, property_id)

    result =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:archive_old, maybe_archive_old_contract(scope, old_contract))
      |> Ecto.Multi.insert(:contract, Contract.changeset(%Contract{}, attrs, scope))
      |> Repo.transaction()

    case result do
      {:ok, %{contract: contract}} ->
        broadcast_contract(scope, {:created, contract})

        unless is_nil(old_contract) do
          broadcast_contract(scope, {:deleted, old_contract})
        end

        {:ok, contract}

      {:error, _name, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp maybe_archive_old_contract(_scope, nil) do
    fn _repo, _changes ->
      {:ok, :no_existing_contract}
    end
  end

  defp maybe_archive_old_contract(%Scope{} = scope, %Contract{} = old_contract) do
    fn repo, _changes ->
      old_contract
      |> Contract.archive_changeset(scope)
      |> repo.update()
    end
  end

  defp get_property_id(attrs) do
    Map.get(attrs, "property_id") || Map.get(attrs, :property_id)
  end

  defp maybe_get_contract_for_property(_scope, nil), do: nil

  defp maybe_get_contract_for_property(%Scope{} = scope, property_id) do
    get_contract_for_property(scope, property_id)
  end

  @doc """
  Updates a contract.

  ## Examples

      iex> update_contract(scope, contract, %{field: new_value})
      {:ok, %Contract{}}

      iex> update_contract(scope, contract, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_contract(%Scope{} = scope, %Contract{} = contract, attrs) do
    if contract.user_id != scope.user.id do
      {:error, :unauthorized}
    else
      with {:ok, contract = %Contract{}} <-
             contract
             |> Contract.changeset(attrs, scope)
             |> Repo.update() do
        broadcast_contract(scope, {:updated, contract})
        {:ok, contract}
      end
    end
  end

  @doc """
  Deletes a contract.

  ## Examples

      iex> delete_contract(scope, contract)
      {:ok, %Contract{}}

      iex> delete_contract(scope, contract)
      {:error, %Ecto.Changeset{}}

  """
  def delete_contract(%Scope{} = scope, %Contract{} = contract) do
    if contract.user_id != scope.user.id do
      {:error, :unauthorized}
    else
      with {:ok, contract = %Contract{}} <-
             contract
             |> Contract.archive_changeset(scope)
             |> Repo.update() do
        broadcast_contract(scope, {:deleted, contract})
        {:ok, contract}
      end
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking contract changes.

  ## Examples

      iex> change_contract(scope, contract)
      %Ecto.Changeset{data: %Contract{}}

  """
  def change_contract(%Scope{} = scope, %Contract{} = contract, attrs \\ %{}) do
    if contract.user_id, do: true = contract.user_id == scope.user.id

    Contract.changeset(contract, attrs, scope)
  end

  @doc """
  Returns the current status of a contract based on its dates.

  ## Return Values
  - `:upcoming` - start_date is in the future
  - `:active` - today is between start_date and end_date
  - `:expired` - end_date is in the past

  ## Examples

      iex> contract_status(%Contract{start_date: ~D[2026-03-01], end_date: ~D[2027-03-01]})
      :upcoming
  """
  def contract_status(%Contract{} = contract) do
    today = Date.utc_today()

    cond do
      Date.compare(today, contract.start_date) == :lt -> :upcoming
      Date.compare(today, contract.end_date) == :gt -> :expired
      true -> :active
    end
  end

  @doc """
  Checks if the current monthly payment is overdue based on expiration_day.

  Only relevant if contract is :active. Checks if current day of month
  is past the expiration_day.

  ## Examples

      iex> payment_overdue?(%Contract{expiration_day: 5})
      true  # if today is after the 5th of current month
  """
  def payment_overdue?(%Contract{} = contract) do
    today = Date.utc_today()
    today.day > contract.expiration_day
  end

  @doc """
  List all contracts for a tenant (as the tenant user) with payments preloaded.

  Note: This is a tenant-scoped operation (the user IS the tenant),
  unlike other functions in this module which are owner-scoped.

  Supports tenants with multiple contracts (e.g., renting multiple properties).

  ## Examples

      iex> list_contracts_for_tenant(scope)
      [%Contract{payments: [%Payment{}, ...]}, ...]

  """
  def list_contracts_for_tenant(%Scope{user: user} = _scope) do
    Contract
    |> where([c], c.tenant_id == ^user.id)
    |> where([c], c.archived == false)
    |> preload([:property, :payments])
    |> Repo.all()
  end

  @doc """
  Gets a single contract for a tenant by ID.

  Returns nil if the contract doesn't exist or doesn't belong to the tenant.

  ## Examples

      iex> get_contract_for_tenant(scope, 123)
      %Contract{}

      iex> get_contract_for_tenant(scope, 456)
      nil

  """
  def get_contract_for_tenant(%Scope{user: user} = _scope, contract_id) do
    Contract
    |> where([c], c.id == ^contract_id)
    |> where([c], c.tenant_id == ^user.id)
    |> where([c], c.archived == false)
    |> preload([:property, :payments])
    |> Repo.one()
  end

  @doc """
  Calculate the current payment number based on months since start_date.
  Returns 0 if the contract hasn't started yet.

  ## Examples

      iex> get_current_payment_number(%Contract{start_date: ~D[2026-01-01]})
      5  # if today is May 2026

      iex> get_current_payment_number(%Contract{start_date: ~D[2026-12-01]})
      0  # if today is earlier than December 2026

  """
  def get_current_payment_number(%Contract{start_date: start_date}) do
    today = Date.utc_today()

    if Date.compare(today, start_date) == :lt do
      0
    else
      months_diff = (today.year - start_date.year) * 12 + (today.month - start_date.month)
      months_diff + 1
    end
  end

  @doc """
  Get list of payment numbers up to current month.
  Returns empty list if the contract hasn't started yet.

  ## Examples

      iex> get_months_up_to_current(%Contract{start_date: ~D[2026-01-01]})
      [1, 2, 3, 4, 5]  # if today is May 2026

      iex> get_months_up_to_current(%Contract{start_date: ~D[2026-12-01]})
      []  # if today is earlier than December 2026

  """
  def get_months_up_to_current(%Contract{} = contract) do
    case get_current_payment_number(contract) do
      0 -> []
      current -> Enum.to_list(1..current)
    end
  end

  @doc """
  Calculate the due date for a specific payment number.

  ## Examples

      iex> calculate_due_date(%Contract{start_date: ~D[2026-01-01], expiration_day: 10}, 3)
      ~D[2026-03-10]

  """
  def calculate_due_date(%Contract{start_date: start_date, expiration_day: exp_day}, payment_num) do
    month_offset = payment_num - 1
    year = start_date.year + div(start_date.month + month_offset - 1, 12)
    month = rem(start_date.month + month_offset - 1, 12) + 1
    last_day = Calendar.ISO.days_in_month(year, month)
    day = min(exp_day, last_day)

    Date.new!(year, month, day)
  end

  @doc """
  Determine contract payment status: :overdue, :on_time, :paid, or :upcoming.

  Returns :upcoming if the contract hasn't started yet.

  ## Examples

      iex> contract_payment_status(scope, contract)
      :on_time

  """
  def contract_payment_status(%Scope{} = scope, %Contract{} = contract) do
    alias Vivvo.Payments

    current_payment_num = get_current_payment_number(contract)

    # Contract hasn't started yet
    if current_payment_num == 0 do
      :upcoming
    else
      determine_active_contract_status(scope, contract, current_payment_num)
    end
  end

  defp determine_active_contract_status(scope, contract, current_payment_num) do
    alias Vivvo.Payments

    today = Date.utc_today()
    current_paid = Payments.month_fully_paid?(scope, contract, current_payment_num)

    past_unpaid_overdue =
      has_past_unpaid_overdue_months?(scope, contract, current_payment_num, today)

    cond do
      current_paid -> :paid
      past_unpaid_overdue -> :overdue
      true -> :on_time
    end
  end

  defp has_past_unpaid_overdue_months?(_scope, _contract, 1, _today), do: false

  defp has_past_unpaid_overdue_months?(scope, contract, current_payment_num, today) do
    alias Vivvo.Payments

    1..(current_payment_num - 1)
    |> Enum.any?(fn num ->
      not Payments.month_fully_paid?(scope, contract, num) and
        month_overdue?(contract, num, today)
    end)
  end

  defp month_overdue?(%Contract{} = contract, payment_num, today) do
    due_date = calculate_due_date(contract, payment_num)
    Date.compare(today, due_date) == :gt
  end

  # Dashboard Analytics Functions

  @doc """
  Get all active contracts with full details for dashboard analytics.

  Preloads property, tenant, and payments for comprehensive data.

  ## Examples

      iex> list_active_contracts_with_details(scope)
      [%Contract{property: %Property{}, tenant: %User{}, payments: [...]}, ...]

  """
  def list_active_contracts_with_details(%Scope{} = scope) do
    today = Date.utc_today()

    Contract
    |> where([c], c.user_id == ^scope.user.id)
    |> where([c], c.archived == false)
    |> where([c], c.start_date <= ^today)
    |> where([c], c.end_date >= ^today)
    |> preload([:property, :tenant, :payments])
    |> order_by([c], asc: c.start_date)
    |> Repo.all()
  end

  @doc """
  Calculate property performance metrics.

  Returns a list of property performance data including:
  - total_income: Total rent collected
  - collection_rate: Percentage of rent collected
  - avg_delay_days: Average payment delay in days
  - active_tenants: Number of active tenants

  ## Examples

      iex> property_performance_metrics(scope)
      [%{property: %Property{}, total_income: Decimal.new("..."), ...}, ...]

  """
  def property_performance_metrics(%Scope{} = scope) do
    contracts = list_active_contracts_with_details(scope)

    contracts
    |> Enum.group_by(& &1.property)
    |> Enum.map(fn {property, property_contracts} ->
      calculate_property_metrics(property, property_contracts, scope)
    end)
    |> Enum.sort_by(& &1.collection_rate)
  end

  defp calculate_property_metrics(property, contracts, scope) do
    alias Vivvo.Payments

    # Calculate total expected rent for active contracts
    total_expected =
      Enum.reduce(contracts, Decimal.new(0), fn contract, acc ->
        Decimal.add(acc, contract.rent)
      end)

    # Calculate received income for current month
    total_received =
      Enum.reduce(contracts, Decimal.new(0), fn contract, acc ->
        current_payment_num = get_current_payment_number(contract)

        received =
          if current_payment_num > 0 do
            Payments.total_accepted_for_month(scope, contract.id, current_payment_num)
          else
            Decimal.new(0)
          end

        Decimal.add(acc, received)
      end)

    # Calculate collection rate
    collection_rate =
      if Decimal.compare(total_expected, Decimal.new(0)) == :gt do
        Decimal.to_float(
          Decimal.mult(Decimal.div(total_received, total_expected), Decimal.new(100))
        )
      else
        0.0
      end

    # Calculate average delay across all payments
    all_payments =
      Enum.flat_map(contracts, & &1.payments)
      |> Enum.filter(&(&1.status == :accepted))

    avg_delay_days =
      case all_payments do
        [] ->
          0

        payments ->
          total_delay =
            Enum.reduce(payments, 0, fn payment, acc ->
              acc + payment_delay(payment, contracts)
            end)

          Float.round(total_delay / length(payments), 1)
      end

    %{
      property: property,
      total_income: total_received,
      collection_rate: collection_rate,
      avg_delay_days: avg_delay_days,
      active_tenants: length(contracts),
      total_expected: total_expected
    }
  end

  defp payment_delay(payment, contracts) do
    contract = Enum.find(contracts, &(&1.id == payment.contract_id))

    case contract do
      nil -> 0
      _ -> calculate_delay(contract, payment)
    end
  end

  defp calculate_delay(contract, payment) do
    due_date = calculate_due_date(contract, payment.payment_number)
    payment_date = DateTime.to_date(payment.inserted_at)
    delay = Date.diff(payment_date, due_date)
    max(0, delay)
  end

  @doc """
  Get dashboard summary statistics.

  Returns a map with key metrics:
  - total_properties: Count of properties
  - total_contracts: Count of active contracts
  - total_tenants: Count of unique tenants
  - occupancy_rate: Percentage of properties with active contracts

  ## Examples

      iex> dashboard_summary(scope)
      %{total_properties: 5, total_contracts: 4, total_tenants: 4, occupancy_rate: 80.0}

  """
  def dashboard_summary(%Scope{} = scope) do
    properties = Vivvo.Properties.list_properties(scope)
    contracts = list_active_contracts_with_details(scope)

    total_properties = length(properties)
    total_contracts = length(contracts)

    unique_tenants =
      contracts
      |> Enum.map(& &1.tenant_id)
      |> Enum.uniq()
      |> length()

    occupancy_rate =
      if total_properties > 0 do
        Float.round(total_contracts / total_properties * 100, 1)
      else
        0.0
      end

    %{
      total_properties: total_properties,
      total_contracts: total_contracts,
      total_tenants: unique_tenants,
      occupancy_rate: occupancy_rate
    }
  end
end
