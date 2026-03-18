defmodule Vivvo.Contracts do
  @moduledoc """
  The Contracts context.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Vivvo.Accounts.Scope
  alias Vivvo.Contracts.Contract
  alias Vivvo.Contracts.RentPeriod
  alias Vivvo.Payments
  alias Vivvo.Properties.Property
  alias Vivvo.Repo

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
    Contract
    |> where([c], c.id == ^id and c.user_id == ^scope.user.id and c.archived == false)
    |> preload([:tenant, :property, :rent_periods])
    |> Repo.one!()
  end

  @doc """
  Gets the current active contract for a specific property as of the given date.

  Returns nil if no active contract exists for the date, or the contract struct with tenant preloaded.

  ## Examples

      iex> current_contract_for_property(scope, 123, ~D[2026-03-15])
      %Contract{tenant: %User{}}

      iex> current_contract_for_property(scope, 456, ~D[2026-03-15])
      nil
  """
  def current_contract_for_property(%Scope{} = scope, property_id, today \\ Date.utc_today()) do
    from(c in Contract,
      where:
        c.property_id == ^property_id and
          c.user_id == ^scope.user.id and
          c.archived == false and
          c.start_date <= ^today and
          c.end_date >= ^today,
      preload: [:tenant, :payments, :rent_periods]
    )
    |> Repo.one()
  end

  @doc """
  Creates a contract.

  ## Options

    * `:past_start_date?` - When set to `true` along with `:update_factor`, allows
      creating contracts with start dates in the past. Used for testing/seeding.
    * `:update_factor` - The index value (as Decimal or float) used to calculate
      rent increases for each subsequent rent period when `:past_start_date?` is true.
    * `:today` - The reference date to use for determining "today". Defaults to
      `Date.utc_today()`. Useful for testing date-dependent behavior.

  Both `:past_start_date?` and `:update_factor` must be provided together for past date support.

  ## Examples

      iex> create_contract(scope, %{field: value})
      {:ok, %Contract{}}

      iex> create_contract(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

      iex> create_contract(scope, attrs, past_start_date?: true, update_factor: 0.05)
      {:ok, %Contract{}}  # Creates contract with multiple historical rent periods

  """
  def create_contract(%Scope{} = scope, attrs, opts \\ []) do
    # Validate options first
    past_start_date? = Keyword.get(opts, :past_start_date?, false)
    update_factor = Keyword.get(opts, :update_factor)
    today = Keyword.get(opts, :today, Date.utc_today())

    validate_opts(past_start_date?, update_factor)

    # Use Ecto.Multi to handle the sequential operations and roll back if any step fails
    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(
        :contract,
        Contract.creation_changeset(%Contract{}, attrs, scope,
          past_start_date?: past_start_date?,
          today: today
        )
      )
      |> Ecto.Multi.run(:rent_periods, fn repo, %{contract: contract} ->
        insert_historical_rent_periods(repo, contract, contract.rent, update_factor, today)
      end)

    # Execute the multi and handle results
    multi
    |> Repo.transaction()
    |> case do
      {:ok, %{contract: contract}} ->
        contract = Repo.preload(contract, :rent_periods)
        broadcast_contract(scope, {:created, contract})
        {:ok, contract}

      {:error, :rent_periods, error, _changes} ->
        {:error, :rent_periods, error}

      {:error, _name, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp validate_opts(past_start_date?, update_factor) do
    if past_start_date? and is_nil(update_factor) do
      raise ArgumentError, "update_factor option must be provided when past_start_date? is true"
    end

    :ok
  end

  defp insert_historical_rent_periods(repo, contract, initial_rent, update_factor, today) do
    rent_periods =
      generate_historical_rent_periods(contract, initial_rent, update_factor, today)
      |> Enum.map(fn period ->
        now =
          DateTime.utc_now()
          |> DateTime.truncate(:second)

        period
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    repo.insert_all(RentPeriod, rent_periods)
    {:ok, rent_periods}
  end

  defp generate_historical_rent_periods(
         contract,
         initial_rent,
         update_factor,
         today
       ) do
    generate_contract_period_dates(contract, today)
    |> Enum.with_index()
    |> Enum.map(fn {period, idx} ->
      rent_value = compute_rent_value(initial_rent, update_factor, idx)

      period
      |> Map.put(:contract_id, contract.id)
      |> Map.put(:index_type, contract.index_type)
      # If idx = 0 set index value to nil
      |> Map.put(:update_factor, (idx > 0 && update_factor) || nil)
      |> Map.put(:value, rent_value)
    end)
  end

  defp generate_contract_period_dates(%Contract{rent_period_duration: nil} = contract, _today) do
    [
      %{
        start_date: contract.start_date,
        end_date: contract.end_date
      }
    ]
  end

  defp generate_contract_period_dates(contract, today) do
    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(&contract_period_date(contract, &1))
    |> Stream.take_while(fn period ->
      # Before or equal to today
      Date.compare(period.start_date, today) != :gt
    end)
    |> Enum.to_list()
  end

  defp contract_period_date(%Contract{rent_period_duration: duration} = contract, num) do
    period_start =
      contract.start_date
      |> Date.beginning_of_month()
      |> Date.shift(month: (num - 1) * duration)
      |> then(&Enum.max([&1, contract.start_date], Date))

    period_end = period_end_date(contract.rent_period_duration, period_start, contract.end_date)

    %{
      start_date: period_start,
      end_date: period_end
    }
  end

  def period_end_date(duration, start_date, max_end_date) do
    start_date
    |> Date.shift(month: duration - 1)
    |> Date.end_of_month()
    |> then(&Enum.min([&1, max_end_date], Date))
  end

  defp compute_rent_value(initial_rent, _update_factor, 0), do: initial_rent

  defp compute_rent_value(initial_rent, update_factor, period_idx) do
    multiplier = decimal_pow(update_factor, period_idx)
    Decimal.mult(initial_rent, multiplier)
  end

  # Calculates base^exp using pure Decimal arithmetic for precision
  defp decimal_pow(_base, 0), do: Decimal.new(1)
  defp decimal_pow(base, 1), do: base

  defp decimal_pow(base, exp) when exp > 1 do
    half = decimal_pow(base, div(exp, 2))
    result = Decimal.mult(half, half)

    if rem(exp, 2) == 0 do
      result
    else
      Decimal.mult(result, base)
    end
  end

  @doc """
  Finds any overlapping contract for the given property and date range.

  Returns the overlapping contract struct if found, or nil if no overlap exists.

  ## Examples

      iex> find_overlapping_contract(scope, 123, ~D[2026-01-01], ~D[2026-12-31])
      nil

      iex> find_overlapping_contract(scope, 123, ~D[2026-01-01], ~D[2026-12-31])
      %Contract{}

  """
  def find_overlapping_contract(%Scope{} = scope, property_id, start_date, end_date) do
    Contract
    |> where([c], c.property_id == ^property_id)
    |> where([c], c.user_id == ^scope.user.id)
    |> where([c], c.archived == false)
    |> where([c], c.start_date <= ^end_date)
    |> where([c], c.end_date >= ^start_date)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Checks if there are any non-archived contracts for the given property
  that overlap with the specified date range.

  Returns {:ok, nil} if no overlap found, or {:error, {:overlap, contract}} if overlap exists.

  ## Examples

      iex> check_overlapping_contracts(scope, 123, ~D[2026-01-01], ~D[2026-12-31])
      {:ok, nil}

      iex> check_overlapping_contracts(scope, 123, ~D[2026-01-01], ~D[2026-12-31])
      {:error, {:overlap, %Contract{}}}

  """
  def check_overlapping_contracts(%Scope{} = scope, property_id, start_date, end_date) do
    case find_overlapping_contract(scope, property_id, start_date, end_date) do
      nil -> {:ok, nil}
      contract -> {:error, {:overlap, contract}}
    end
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
    with :ok <- authorize_contract(contract, scope),
         {:ok, contract = %Contract{}} <-
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
    with :ok <- authorize_contract(contract, scope),
         {:ok, contract = %Contract{}} <-
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
    Contract.changeset(contract, attrs, scope)
  end

  # Authorizes that the contract belongs to the scope user
  defp authorize_contract(%Contract{user_id: user_id}, %Scope{user: %{id: scope_user_id}}) do
    if user_id == scope_user_id do
      :ok
    else
      {:error, :unauthorized}
    end
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

      iex> payment_overdue?(%Contract{expiration_day: 5}, ~D[2024-01-10])
      true

      iex> payment_overdue?(%Contract{expiration_day: 10}, ~D[2024-01-05])
      false
  """
  def payment_overdue?(%Contract{} = contract, today \\ Date.utc_today()) do
    today.day > contract.expiration_day
  end

  @doc """
  List all contracts for a tenant (as the tenant user) with payments and files preloaded.

  Note: This is a tenant-scoped operation (the user IS the tenant),
  unlike other functions in this module which are owner-scoped.

  Supports tenants with multiple contracts (e.g., renting multiple properties).

  ## Examples

      iex> list_contracts_for_tenant(scope)
      [%Contract{payments: [%Payment{files: [...]}, ...]}, ...]

  """
  def list_contracts_for_tenant(%Scope{user: user} = _scope) do
    Contract
    |> where([c], c.tenant_id == ^user.id)
    |> where([c], c.archived == false)
    |> preload([:property, :rent_periods, payments: [:files]])
    |> Repo.all()
  end

  @doc """
  Gets a single contract for a tenant by ID with payments and files preloaded.

  Returns nil if the contract doesn't exist or doesn't belong to the tenant.

  ## Examples

      iex> get_contract_for_tenant(scope, 123)
      %Contract{payments: [%Payment{files: [...]}]}

      iex> get_contract_for_tenant(scope, 456)
      nil

  """
  def get_contract_for_tenant(%Scope{user: user} = _scope, contract_id) do
    Contract
    |> where([c], c.id == ^contract_id)
    |> where([c], c.tenant_id == ^user.id)
    |> where([c], c.archived == false)
    |> preload([:property, :rent_periods, payments: [:files]])
    |> Repo.one()
  end

  @doc """
  Calculate the current payment number based on months since start_date.
  Returns 0 if the contract hasn't started yet.
  Caps the result at the contract's total expected number of payments.

  ## Examples

      iex> get_current_payment_number(%Contract{start_date: ~D[2026-01-01], end_date: ~D[2026-12-31]})
      5  # if today is May 2026

      iex> get_current_payment_number(%Contract{start_date: ~D[2026-12-01], end_date: ~D[2027-12-31]})
      0  # if today is earlier than December 2026

      iex> get_current_payment_number(%Contract{start_date: ~D[2025-01-01], end_date: ~D[2025-03-31]})
      3  # expired contract returns total payments, not inflated number

  """
  def get_current_payment_number(%Contract{} = contract) do
    today = Date.utc_today()
    start_date = contract.start_date

    if Date.compare(today, start_date) == :lt do
      0
    else
      months_diff = (today.year - start_date.year) * 12 + (today.month - start_date.month)
      current = months_diff + 1
      total = contract_duration_months(contract)
      min(current, total)
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
      []  # empty range - no due dates in the past yet

  """
  def get_past_payment_numbers(%Contract{} = contract, today) do
    current = get_current_payment_number(contract)
    current_due_date = calculate_due_date(contract, current)

    last =
      if Date.compare(current_due_date, today) in [:lt, :eq],
        do: current,
        else: current - 1

    if last >= 1 do
      Enum.to_list(1..last)
    else
      []
    end
  end

  @doc """
  Calculate the due date for a specific payment number.

  ## Examples

      iex> calculate_due_date(%Contract{start_date: ~D[2026-01-01], expiration_day: 10}, 3)
      ~D[2026-03-10]

  """
  def calculate_due_date(%Contract{start_date: start_date, expiration_day: exp_day}, payment_num) do
    shifted_date = Date.shift(start_date, month: payment_num - 1)
    last_day = Date.days_in_month(shifted_date)
    day = min(exp_day, last_day)

    %{shifted_date | day: day}
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
    |> preload([:property, :tenant, :rent_periods, :payments])
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
    |> preload(contract: [:tenant, :rent_periods, :payments])
    |> Repo.all()
    |> Enum.map(&calculate_property_metrics(&1, &1.contract, scope))
  end

  defp calculate_property_metrics(property, nil = _contract, _scope) do
    %{
      property: property,
      total_income: Decimal.new(0),
      collection_rate: 0.0,
      avg_delay_days: 0.0,
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
          avg_delay_days: 0.0,
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

    total_expected =
      Enum.reduce(past_payment_numbers, Decimal.new(0), fn payment_num, acc ->
        due_date = calculate_due_date(contract, payment_num)
        rent = current_rent_value(contract, due_date)
        Decimal.add(acc, rent)
      end)

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
    rent = current_rent_value(contract, due_date)

    cond do
      is_nil(month_payments) ->
        # No payments at all for this month
        max(0, Date.diff(today, due_date))

      month_fully_paid?(month_payments, rent) ->
        # Fully paid - find completion payment and calculate delay
        calculate_completion_delay(month_payments, rent, due_date)

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
    days_from_today(end_date)
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
    days_from_today(start_date)
  end

  # Shared helper for calculating days from today to a target date
  defp days_from_today(date) do
    today = Date.utc_today()

    case Date.compare(date, today) do
      :gt -> Date.diff(date, today)
      :eq -> 0
      :lt -> nil
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
    due_date = calculate_due_date(contract, payment_num)
    rent = current_rent_value(contract, due_date)
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
          payments: [%Payment{files: [...]}]
        }
      ]

  """
  def get_payment_statuses(%Scope{} = scope, %Contract{} = contract) do
    current_payment_num = get_current_payment_number(contract)
    today = Date.utc_today()

    if current_payment_num == 0 do
      []
    else
      # Fetch all payments for the contract with files preloaded
      contract_payments = Payments.list_payments_for_contract(scope, contract.id)
      totals_by_month = calculate_totals_by_month(contract_payments)

      Enum.map(
        1..current_payment_num,
        &build_payment_status(&1, contract, contract_payments, totals_by_month, today)
      )
    end
  end

  defp calculate_totals_by_month(contract_payments) do
    contract_payments
    |> Enum.filter(&(&1.status == :accepted))
    |> Enum.group_by(& &1.payment_number)
    |> Map.new(fn {num, payments} ->
      {num, Enum.reduce(payments, Decimal.new(0), &Decimal.add(&2, &1.amount))}
    end)
  end

  defp build_payment_status(payment_num, contract, contract_payments, totals_by_month, today) do
    due_date = calculate_due_date(contract, payment_num)
    rent = current_rent_value(contract, due_date)
    total_paid = Map.get(totals_by_month, payment_num, Decimal.new(0))
    month_status = determine_month_status(total_paid, rent)

    %{
      payment_number: payment_num,
      due_date: due_date,
      rent: rent,
      total_paid: total_paid,
      status: month_status,
      is_overdue: month_overdue?(contract, payment_num, today) and month_status != :paid,
      days_until_due: Date.diff(due_date, today),
      payments: get_month_payments(contract_payments, payment_num)
    }
  end

  defp determine_month_status(total_paid, rent) do
    cond do
      Decimal.compare(total_paid, rent) != :lt -> :paid
      Decimal.compare(total_paid, Decimal.new(0)) == :gt -> :partial
      true -> :unpaid
    end
  end

  defp get_month_payments(contract_payments, payment_num) do
    contract_payments
    |> Enum.filter(&(&1.payment_number == payment_num))
    |> Enum.sort_by(& &1.inserted_at, :desc)
  end

  @doc """
  Returns the due date of the next upcoming payment, or nil if contract has ended.

  ## Examples

      iex> next_payment_date(contract)
      ~D[2026-04-10]

      iex> next_payment_date(ended_contract)
      nil

  """
  def next_payment_date(%Contract{} = contract) do
    current = get_current_payment_number(contract)
    total = contract_duration_months(contract)

    if current < total do
      calculate_due_date(contract, current + 1)
    else
      nil
    end
  end

  @doc """
  Calculate the total number of months in a contract period.

  ## Examples

      iex> contract_duration_months(%Contract{start_date: ~D[2026-01-01], end_date: ~D[2026-12-31]})
      12
  """
  @spec contract_duration_months(Contract.t()) :: integer()
  def contract_duration_months(%Contract{start_date: start_date, end_date: end_date}) do
    (end_date.year - start_date.year) * 12 + (end_date.month - start_date.month) + 1
  end

  @doc """
  Returns the rent period that covers the given date for a contract.

  ## Behavior

  - If the date falls within a rent period's date range, returns that period
  - If the contract is in the future (start_date > date), returns the earliest period
  - If the contract is expired (end_date < date), returns the latest period
  - If no period covers the date and contract is active, raises an error
    (this indicates a bug in period generation)

  ## Examples

      iex> current_rent_period(contract_with_periods, ~D[2026-03-15])
      %RentPeriod{start_date: ~D[2026-01-01], end_date: ~D[2026-03-31], value: Decimal.new("1200.00")}

      iex> current_rent_period(future_contract, Date.utc_today())
      %RentPeriod{}  # Returns earliest period for future contracts

  """
  def current_rent_period(%Contract{} = contract, date \\ Date.utc_today()) do
    contract =
      if Ecto.assoc_loaded?(contract.rent_periods) do
        contract
      else
        Logger.warning(
          "Rent periods not preloaded for contract #{contract.id} in current_rent_period. Preloading now, but consider preloading in calling function for efficiency."
        )

        Repo.preload(contract, :rent_periods)
      end

    periods = contract.rent_periods

    date_match =
      Enum.find(periods, fn rp ->
        Date.compare(rp.start_date, date) != :gt and
          Date.compare(rp.end_date, date) != :lt
      end)

    case date_match do
      %RentPeriod{} = rp ->
        rp

      nil ->
        handle_no_matching_period(contract, periods, date)
    end
  end

  defp handle_no_matching_period(contract, periods, date) do
    cond do
      Date.compare(contract.start_date, date) == :gt ->
        # Future contract -- use the initial (earliest) period
        Enum.min_by(periods, & &1.start_date, Date, fn ->
          raise "Contract #{contract.id} has no rent periods"
        end)

      Date.compare(contract.end_date, date) == :lt ->
        # Expired contract -- use the latest period
        Enum.max_by(periods, & &1.end_date, Date, fn ->
          raise "Contract #{contract.id} has no rent periods"
        end)

      true ->
        # Contract is active but no matching period -- bug in period generation
        raise "Contract #{contract.id} has no current rent period for date #{date}. " <>
                "This indicates a bug in rent period generation."
    end
  end

  @doc """
  Returns the rent value for the given date from the appropriate rent period.

  ## Examples

      iex> current_rent_value(contract, ~D[2026-03-15])
      Decimal.new("1200.00")

  """
  def current_rent_value(%Contract{} = contract, date \\ Date.utc_today()) do
    current_rent_period(contract, date).value
  end

  @doc """
  Returns the next rent update date based on the current rent period.

  Returns nil if:
  - The contract has no rent periods
  - The contract has no indexing configured (no rent_period_duration or index_type)
  - The contract has ended
  - The next update would be after the contract's end date

  ## Examples

      iex> next_rent_update_date(contract)
      ~D[2026-04-01]

  """
  def next_rent_update_date(%Contract{} = contract) do
    today = Date.utc_today()
    current_period = current_rent_period(contract, today)
    update_date = Date.add(current_period.end_date, 1)

    if Date.after?(update_date, contract.end_date) do
      nil
    else
      update_date
    end
  end

  @doc """
  Calculate days until the next rent update.

  Returns nil if there is no next update (contract has ended, no indexing configured, etc.)
  Returns 0 if the update is today.

  ## Examples

      iex> days_until_next_update(contract)
      15

      iex> days_until_next_update(contract_without_indexing)
      nil

  """
  def days_until_next_update(%Contract{} = contract) do
    case next_rent_update_date(contract) do
      nil -> nil
      date -> Date.diff(date, Date.utc_today())
    end
  end

  @doc """
  Creates a rent period. Used by system jobs only (no scope validation).

  Uses `ON CONFLICT DO NOTHING` to handle race conditions gracefully when
  multiple workers attempt to create the same rent period concurrently.

  ## Examples

      iex> create_rent_period(%{field: value})
      {:ok, %RentPeriod{}}

      iex> create_rent_period(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

      iex> create_rent_period(attrs)  # when period already exists
      {:ok, :already_exists}

  """
  def create_rent_period(attrs) do
    %RentPeriod{}
    |> RentPeriod.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:contract_id, :start_date]
    )
    |> handle_rent_period_insert_result(attrs)
  end

  defp handle_rent_period_insert_result({:ok, %RentPeriod{id: nil} = _struct}, _attrs) do
    # ON CONFLICT :nothing was triggered - period already exists
    {:ok, :already_exists}
  end

  defp handle_rent_period_insert_result({:ok, %RentPeriod{} = rent_period}, _attrs) do
    {:ok, rent_period}
  end

  defp handle_rent_period_insert_result({:error, changeset}, _attrs) do
    {:error, changeset}
  end

  @doc """
  Gets a single contract by ID without scope validation. Used by system jobs.

  Returns nil if the Contract does not exist.

  ## Examples

      iex> get_system_contract(123)
      %Contract{}

      iex> get_system_contract(456)
      nil

  """
  def get_system_contract(id) do
    Contract
    |> where([c], c.id == ^id and c.archived == false)
    |> preload([:rent_periods])
    |> Repo.one()
  end

  @doc """
  Returns a list of contracts whose latest rent period ends in the given month
  and need a new rent period created. Used by the monthly scheduler worker.

  Filters for:
  - Non-archived contracts that haven't ended
  - Contracts with index_type and rent_period_duration configured
  - Latest rent period ends in the current month
  - Contract extends beyond the latest period's end date

  ## Examples

      iex> contracts_needing_update(~D[2026-05-25])
      [%Contract{}, ...]

  """
  def contracts_needing_update(%Date{} = today) do
    # Subquery to get the latest rent period end_date for each contract
    latest_periods_query =
      from(rp in RentPeriod,
        group_by: rp.contract_id,
        select: %{
          contract_id: rp.contract_id,
          latest_end_date: max(rp.end_date)
        }
      )

    from(c in Contract,
      join: latest in subquery(latest_periods_query),
      on: latest.contract_id == c.id,
      where: c.archived == false,
      where: c.end_date > ^today,
      where: not is_nil(c.rent_period_duration),
      where: not is_nil(c.index_type),
      # Latest period ends in current month
      where: fragment("EXTRACT(YEAR FROM ?) = ?", latest.latest_end_date, ^today.year),
      where: fragment("EXTRACT(MONTH FROM ?) = ?", latest.latest_end_date, ^today.month),
      # Contract extends beyond the latest period's end date
      where: c.end_date > latest.latest_end_date
    )
    |> Repo.all()
  end
end
