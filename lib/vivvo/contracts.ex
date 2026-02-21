defmodule Vivvo.Contracts do
  @moduledoc """
  The Contracts context.
  """

  import Ecto.Query, warn: false
  alias Vivvo.Repo

  alias Vivvo.Accounts.Scope
  alias Vivvo.Contracts.Contract
  alias Vivvo.Payments
  alias Vivvo.Properties.Property

  # Threshold (in days) for considering a contract as "ending soon"
  @ending_soon_threshold_days 60

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
    # Only check authorization if the contract already has an owner
    if contract.user_id && contract.user_id != scope.user.id do
      raise "Unauthorized"
    end

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
  def payment_overdue?(%Contract{} = contract, today \\ Date.utc_today()) do
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
  Get range of payment numbers with due dates in the past.

  Returns an Elixir range (e.g., 1..3) representing payment periods whose
  due dates have already passed. Uses O(1) optimization by only checking
  the current payment number's due date - all prior periods are guaranteed past.

  ## Examples

      iex> get_past_payment_numbers(contract, ~D[2026-02-15])
      1..2  # if payment periods 1 and 2 have passed

      iex> get_past_payment_numbers(contract, ~D[2026-01-01])
      1..0  # empty range - no due dates in the past yet

  """
  def get_past_payment_numbers(%Contract{} = contract, today) do
    current = get_current_payment_number(contract)
    current_due_date = calculate_due_date(contract, current)

    last =
      if Date.compare(current_due_date, today) == :lt,
        do: current,
        else: current - 1

    Range.new(1, last, 1)
    |> Enum.to_list()
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
    current_payment_num = get_current_payment_number(contract)

    # Contract hasn't started yet
    if current_payment_num == 0 do
      :upcoming
    else
      determine_active_contract_status(scope, contract, current_payment_num)
    end
  end

  defp determine_active_contract_status(scope, contract, current_payment_num) do
    today = Date.utc_today()
    current_paid = Payments.month_fully_paid?(scope, contract, current_payment_num)

    past_unpaid_overdue =
      has_past_unpaid_overdue_months?(scope, contract, current_payment_num, today)

    current_overdue = month_overdue?(contract, current_payment_num, today)

    cond do
      current_paid -> :paid
      past_unpaid_overdue -> :overdue
      current_overdue -> :overdue
      true -> :on_time
    end
  end

  defp has_past_unpaid_overdue_months?(_scope, _contract, 1, _today), do: false

  defp has_past_unpaid_overdue_months?(scope, contract, current_payment_num, today) do
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
  - state: Property occupancy state (:occupied or :vacant)

  ## Examples

      iex> property_performance_metrics(scope)
      [%{property: %Property{}, total_income: Decimal.new("..."), ...}, ...]

  """
  def property_performance_metrics(%Scope{} = scope) do
    Property
    |> where([p], p.user_id == ^scope.user.id)
    |> where([p], p.archived == false)
    |> order_by([p], asc: p.name)
    |> preload(contract: [:tenant, :payments])
    |> Repo.all()
    |> Enum.map(&calculate_property_metrics(&1, &1.contract, scope))
  end

  defp calculate_property_metrics(property, nil = _contract, _scope) do
    %{
      property: property,
      total_income: Decimal.new(0),
      collection_rate: 0.0,
      avg_delay_days: 0,
      state: :vacant,
      total_expected: Decimal.new(0)
    }
  end

  defp calculate_property_metrics(property, %Contract{} = contract, scope) do
    status = contract_status(contract)

    case status do
      :upcoming ->
        %{
          property: property,
          total_income: Decimal.new(0),
          collection_rate: 0.0,
          avg_delay_days: 0.0,
          state: :upcoming,
          total_expected: Decimal.new(0),
          contract: contract,
          days_until_start: days_until_start(contract),
          days_until_end: nil
        }

      :expired ->
        %{
          property: property,
          total_income: Decimal.new(0),
          collection_rate: 0.0,
          avg_delay_days: 0,
          state: :vacant,
          total_expected: Decimal.new(0)
        }

      :active ->
        calculate_active_property_metrics(property, contract, scope)
    end
  end

  defp calculate_active_property_metrics(property, %Contract{} = contract, scope) do
    today = Date.utc_today()
    past_payment_numbers = get_past_payment_numbers(contract, today)

    periods_count = Enum.count(past_payment_numbers)
    total_expected = Decimal.mult(contract.rent, Decimal.new(periods_count))

    total_received = Payments.total_rent_collected(scope, contract, today)

    collection_rate =
      if periods_count > 0 do
        Decimal.div(total_received, total_expected)
        |> Decimal.mult(Decimal.new(100))
        |> Decimal.to_float()
      else
        0.0
      end

    payments_by_month = Payments.get_contract_payments_by_month(scope, contract.id)

    avg_delay_days = calculate_avg_delay_days(contract, payments_by_month, today)

    %{
      property: property,
      total_income: total_received,
      collection_rate: collection_rate,
      avg_delay_days: avg_delay_days,
      state: :occupied,
      total_expected: total_expected,
      contract: contract,
      days_until_start: nil,
      days_until_end: days_until_end(contract)
    }
  end

  @doc """
  Calculate the average delay days for a contract.

  For each month (payment_number):
  - If fully paid: uses the delay of the payment that completed the rent
  - If partially paid: uses the delay from due date to today

  Early payments are counted as 0 delay (not negative).

  ## Parameters
  - `contract`: The contract struct with rent and due dates info
  - `payments_by_month`: Map of %{payment_number => [payments]} from `Payments.get_contract_payments_by_month/2`
  - `today`: The current date to use for partially paid months

  ## Returns
  Average delay as a float rounded to 1 decimal place, or 0.0 if no months

  ## Examples

      iex> calculate_avg_delay_days(contract, payments_by_month, ~D[2026-02-19])
      3.5

  """
  def calculate_avg_delay_days(%Contract{} = contract, payments_by_month, %Date{} = today) do
    past_payment_numbers = get_past_payment_numbers(contract, today)

    # Handle empty range case
    delays =
      Enum.map(past_payment_numbers, fn payment_number ->
        calculate_month_delay(contract, payments_by_month, payment_number, today)
      end)

    case delays do
      [] -> 0.0
      _ -> Float.round(Enum.sum(delays) / length(delays), 1)
    end
  end

  defp calculate_month_delay(contract, payments_by_month, payment_number, today) do
    due_date = calculate_due_date(contract, payment_number)
    month_payments = Map.get(payments_by_month, payment_number)

    cond do
      is_nil(month_payments) ->
        # No payments at all for this month
        max(0, Date.diff(today, due_date))

      month_fully_paid?(month_payments, contract.rent) ->
        # Fully paid - find completion payment and calculate delay
        calculate_completion_delay(month_payments, contract.rent, due_date)

      true ->
        # Partially paid - use today as completion date
        max(0, Date.diff(today, due_date))
    end
  end

  defp month_fully_paid?(month_payments, rent) do
    total_paid =
      month_payments
      |> Enum.map(& &1.amount)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    Decimal.compare(total_paid, rent) != :lt
  end

  defp calculate_completion_delay(month_payments, rent, due_date) do
    case find_completion_payment(month_payments, rent) do
      nil ->
        0

      completion_payment ->
        payment_date = DateTime.to_date(completion_payment.inserted_at)
        max(0, Date.diff(payment_date, due_date))
    end
  end

  # Private helper to find the completion payment from a list of payments
  # Uses tail recursion to track cumulative sum until rent is reached
  defp find_completion_payment(payments, rent) do
    do_find_completion_payment(payments, rent, Decimal.new(0))
  end

  defp do_find_completion_payment([], _rent, _cumulative), do: nil

  defp do_find_completion_payment([payment | rest], rent, cumulative) do
    new_cumulative = Decimal.add(cumulative, payment.amount)

    if Decimal.compare(new_cumulative, rent) != :lt do
      # This payment completed the rent
      payment
    else
      # Continue to next payment
      do_find_completion_payment(rest, rent, new_cumulative)
    end
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

  @doc """
  Calculate days until contract ends.

  Returns nil if contract has already ended, 0 if it ends today.

  ## Examples

      iex> days_until_end(%Contract{end_date: ~D[2026-12-31]})
      300

      iex> days_until_end(%Contract{end_date: ~D[2020-01-01]})
      nil

  """
  def days_until_end(%Contract{end_date: end_date}) do
    today = Date.utc_today()

    case Date.compare(end_date, today) do
      :gt -> Date.diff(end_date, today)
      :eq -> 0
      :lt -> nil
    end
  end

  @doc """
  Calculate days until contract starts.

  Returns nil if contract has already started, 0 if it starts today.

  ## Examples

      iex> days_until_start(%Contract{start_date: ~D[2026-03-01]})
      10

      iex> days_until_start(%Contract{start_date: ~D[2020-01-01]})
      nil

  """
  def days_until_start(%Contract{start_date: start_date}) do
    today = Date.utc_today()

    case Date.compare(start_date, today) do
      :gt -> Date.diff(start_date, today)
      :eq -> 0
      :lt -> nil
    end
  end

  @doc """
  Check if contract is ending soon (within #{@ending_soon_threshold_days} days).

  ## Examples

      iex> ending_soon?(%Contract{end_date: ~D[2026-03-01]})
      true  # if today is within #{@ending_soon_threshold_days} days of end_date

  """
  def ending_soon?(%Contract{} = contract) do
    case days_until_end(contract) do
      nil -> false
      days -> days > 0 and days <= @ending_soon_threshold_days
    end
  end

  @doc """
  Get a human-readable label for contract status with context.

  ## Examples

      iex> contract_status_label(contract)
      "Ending Soon"

  """
  def contract_status_label(%Contract{} = contract) do
    status = contract_status(contract)

    cond do
      status == :expired -> "Expired"
      ending_soon?(contract) -> "Ending Soon"
      status == :upcoming -> "Upcoming"
      true -> "Active"
    end
  end

  @doc """
  Calculate the total amount due for all unpaid months up to current.

  Returns the sum of outstanding balances across all unpaid months.

  ## Examples

      iex> total_amount_due(scope, contract)
      Decimal.new("1500.00")

  """
  def total_amount_due(%Scope{} = scope, %Contract{} = contract) do
    current_payment_num = get_current_payment_number(contract)
    do_total_amount_due(scope, contract, current_payment_num)
  end

  defp do_total_amount_due(_scope, _contract, 0), do: Decimal.new(0)

  defp do_total_amount_due(scope, contract, current_payment_num) do
    today = Date.utc_today()

    Enum.reduce(1..current_payment_num, Decimal.new(0), fn payment_num, acc ->
      add_outstanding_if_due(scope, contract, payment_num, today, acc)
    end)
  end

  defp add_outstanding_if_due(scope, contract, payment_num, today, acc) do
    due_date = calculate_due_date(contract, payment_num)

    case Date.compare(today, due_date) do
      :lt -> acc
      _ -> calculate_and_add_outstanding(scope, contract, payment_num, acc)
    end
  end

  # Calculates outstanding amount for a month. Returns negative value
  # when total payments exceed rent (overpayment credit).
  defp calculate_and_add_outstanding(scope, contract, payment_num, acc) do
    rent = contract.rent
    paid = Payments.total_accepted_for_month(scope, contract.id, payment_num)
    outstanding = Decimal.sub(rent, paid)
    Decimal.add(acc, outstanding)
  end

  @doc """
  Get the earliest due date among all unpaid months.

  Returns nil if nothing is due.

  ## Examples

      iex> earliest_due_date(scope, contract)
      ~D[2026-02-10]

  """
  def earliest_due_date(%Scope{} = scope, %Contract{} = contract) do
    current_payment_num = get_current_payment_number(contract)

    if current_payment_num == 0 do
      nil
    else
      do_earliest_due_date(scope, contract, current_payment_num)
    end
  end

  defp do_earliest_due_date(scope, contract, current_payment_num) do
    today = Date.utc_today()

    # Get all unpaid months first (single pass), then find earliest due date
    unpaid_months =
      Enum.filter(1..current_payment_num, fn payment_num ->
        not Payments.month_fully_paid?(scope, contract, payment_num)
      end)

    unpaid_months
    |> Enum.map(&calculate_due_date(contract, &1))
    |> Enum.filter(fn due_date -> Date.compare(today, due_date) != :lt end)
    |> case do
      [] -> nil
      dates -> Enum.min(dates)
    end
  end

  @doc """
  Get all payment statuses for a contract up to current month.

  Returns a list of maps with payment info for each month.

  ## Examples

      iex> get_payment_statuses(scope, contract)
      [
        %{
          payment_number: 1,
          due_date: ~D[2026-01-10],
          rent: Decimal.new("500.00"),
          total_paid: Decimal.new("500.00"),
          status: :paid,
          payments: [%Payment{}]
        }
      ]

  """
  def get_payment_statuses(%Scope{} = scope, %Contract{} = contract) do
    current_payment_num = get_current_payment_number(contract)
    today = Date.utc_today()

    if current_payment_num == 0 do
      []
    else
      Enum.map(1..current_payment_num, fn payment_num ->
        due_date = calculate_due_date(contract, payment_num)
        total_paid = Payments.total_accepted_for_month(scope, contract.id, payment_num)
        month_status = Payments.get_month_status(scope, contract, payment_num)

        # Get payments for this month
        month_payments =
          Enum.filter(contract.payments, &(&1.payment_number == payment_num))
          |> Enum.sort_by(& &1.inserted_at, :desc)

        %{
          payment_number: payment_num,
          due_date: due_date,
          rent: contract.rent,
          total_paid: total_paid,
          status: month_status,
          is_overdue: month_overdue?(contract, payment_num, today) and month_status != :paid,
          days_until_due: Date.diff(due_date, today),
          payments: month_payments
        }
      end)
    end
  end

  @doc """
  Get upcoming payments (future months within contract period).

  Returns a list of maps with upcoming payment info.

  ## Examples

      iex> get_upcoming_payments(contract)
      [%{payment_number: 6, due_date: ~D[2026-06-10], rent: Decimal.new("500.00")}]

  """
  def get_upcoming_payments(%Contract{} = contract) do
    current_payment_num = get_current_payment_number(contract)
    total_months = contract_duration_months(contract)

    if current_payment_num >= total_months do
      []
    else
      Enum.map((current_payment_num + 1)..total_months, fn payment_num ->
        %{
          payment_number: payment_num,
          due_date: calculate_due_date(contract, payment_num),
          rent: contract.rent
        }
      end)
    end
  end

  defp contract_duration_months(%Contract{start_date: start_date, end_date: end_date}) do
    (end_date.year - start_date.year) * 12 + (end_date.month - start_date.month) + 1
  end
end
