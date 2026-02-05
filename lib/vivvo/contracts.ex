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
      preload: [:tenant]
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
    true = contract.user_id == scope.user.id

    with {:ok, contract = %Contract{}} <-
           contract
           |> Contract.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_contract(scope, {:updated, contract})
      {:ok, contract}
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
    true = contract.user_id == scope.user.id

    with {:ok, contract = %Contract{}} <-
           contract
           |> Contract.archive_changeset(scope)
           |> Repo.update() do
      broadcast_contract(scope, {:deleted, contract})
      {:ok, contract}
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
end
