defmodule Vivvo.Payments do
  @moduledoc """
  The Payments context.

  ## Payment Period vs Submission Time

  An important distinction in this module is between when a payment is submitted
  (`inserted_at`) and which period the payment is for (payment period).

  The payment period is calculated from:
  - `payment_number`: Which installment of the contract (1, 2, 3, etc.)
  - Contract's `start_date`: When the rental period began

  For example, if a contract starts on January 15th:
  - payment_number 1 is for January (contract month 1)
  - payment_number 2 is for February (contract month 2)
  - etc.

  This means a late payment (e.g., February rent submitted in March) should still
  be counted as February income, not March income. Most analytics functions in this
  module use the payment period, not the submission time, to ensure accurate
  financial reporting.

  Use `payment_target_month/2` to calculate the target month for any payment.
  """

  import Ecto.Query, warn: false
  alias Vivvo.Repo

  alias Vivvo.Accounts.Scope
  alias Vivvo.Contracts.Contract
  alias Vivvo.Payments.Payment

  @decimal_zero Decimal.new(0)

  @doc """
  Subscribes to scoped notifications about any payment changes.

  The broadcasted messages match the pattern:

    * {:created, %Payment{}}
    * {:updated, %Payment{}}
    * {:deleted, %Payment{}}

  """
  def subscribe_payments(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(Vivvo.PubSub, "user:#{key}:payments")
  end

  defp broadcast_payment(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(Vivvo.PubSub, "user:#{key}:payments", message)
  end

  @doc """
  Returns the list of payments.

  ## Examples

      iex> list_payments(scope)
      [%Payment{}, ...]

  """
  def list_payments(%Scope{} = scope) do
    Repo.all_by(Payment, user_id: scope.user.id)
  end

  @doc """
  Gets a single payment.

  Returns nil if the Payment does not exist.

  ## Examples

      iex> get_payment(scope, 123)
      %Payment{}

      iex> get_payment(scope, 456)
      nil

  """
  def get_payment(%Scope{} = scope, id) do
    from(p in Payment,
      left_join: c in assoc(p, :contract),
      where:
        p.id == ^id and
          (p.user_id == ^scope.user.id or (not is_nil(c) and c.user_id == ^scope.user.id)),
      preload: [contract: c]
    )
    |> Repo.one()
  end

  @doc """
  Gets a single payment.

  Raises `Ecto.NoResultsError` if the Payment does not exist.

  ## Examples

      iex> get_payment!(scope, 123)
      %Payment{}

      iex> get_payment!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_payment!(%Scope{} = scope, id) do
    from(p in Payment,
      left_join: c in assoc(p, :contract),
      where:
        p.id == ^id and
          (p.user_id == ^scope.user.id or (not is_nil(c) and c.user_id == ^scope.user.id)),
      preload: [contract: c]
    )
    |> Repo.one!()
  end

  @doc """
  Creates a payment.

  ## Options

    * `:remaining_allowance` - The maximum remaining amount allowed for this payment period

  ## Examples

      iex> create_payment(scope, %{field: value})
      {:ok, %Payment{}}

      iex> create_payment(scope, %{field: bad_value}, remaining_allowance: Decimal.new("100"))
      {:error, %Ecto.Changeset{}}

  """
  def create_payment(%Scope{} = scope, attrs, opts \\ []) do
    contract_id = Map.get(attrs, "contract_id") || Map.get(attrs, :contract_id)

    with :ok <- validate_contract_ownership(scope, contract_id),
         {:ok, payment = %Payment{}} <-
           %Payment{}
           |> Payment.changeset(attrs, scope, opts)
           |> Repo.insert() do
      broadcast_payment(scope, {:created, payment})
      {:ok, payment}
    end
  end

  defp validate_contract_ownership(_scope, nil), do: :ok

  defp validate_contract_ownership(scope, contract_id) do
    case Vivvo.Contracts.get_contract_for_tenant(scope, contract_id) do
      nil -> {:error, :unauthorized}
      _contract -> :ok
    end
  end

  @doc """
  Updates a payment.

  ## Examples

      iex> update_payment(scope, payment, %{field: new_value})
      {:ok, %Payment{}}

      iex> update_payment(scope, payment, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_payment(%Scope{} = scope, %Payment{} = payment, attrs, opts \\ []) do
    if payment.user_id != scope.user.id do
      {:error, :unauthorized}
    else
      with {:ok, payment = %Payment{}} <-
             payment
             |> Payment.changeset(attrs, scope, opts)
             |> Repo.update() do
        broadcast_payment(scope, {:updated, payment})
        {:ok, payment}
      end
    end
  end

  @doc """
  Deletes a payment.

  ## Examples

      iex> delete_payment(scope, payment)
      {:ok, %Payment{}}

      iex> delete_payment(scope, payment)
      {:error, %Ecto.Changeset{}}

  """
  def delete_payment(%Scope{} = scope, %Payment{} = payment) do
    if payment.user_id != scope.user.id do
      {:error, :unauthorized}
    else
      with {:ok, payment = %Payment{}} <-
             Repo.delete(payment) do
        broadcast_payment(scope, {:deleted, payment})
        {:ok, payment}
      end
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking payment changes.

  ## Options

    * `:remaining_allowance` - The maximum remaining amount allowed for this payment period

  ## Examples

      iex> change_payment(scope, payment)
      %Ecto.Changeset{data: %Payment{}}

  """
  def change_payment(%Scope{} = scope, %Payment{} = payment, attrs \\ %{}, opts \\ []) do
    Payment.changeset(payment, attrs, scope, opts)
  end

  @doc """
  List all payments for the tenant's contracts.

  ## Examples

      iex> list_payments_for_tenant(scope)
      [%Payment{}, ...]

  """
  def list_payments_for_tenant(%Scope{user: user} = _scope) do
    Payment
    |> join(:inner, [p], c in assoc(p, :contract))
    |> where([p, c], c.tenant_id == ^user.id)
    |> preload([:contract])
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  @doc """
  List all payments for a specific contract.

  ## Examples

      iex> list_payments_for_contract(scope, contract_id)
      [%Payment{}, ...]

  """
  def list_payments_for_contract(%Scope{} = scope, contract_id) do
    Payment
    |> where([p], p.contract_id == ^contract_id)
    |> where([p], p.user_id == ^scope.user.id)
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  @doc """
  Accept a payment (owner action).

  ## Examples

      iex> accept_payment(scope, payment)
      {:ok, %Payment{}}

  """
  def accept_payment(%Scope{} = scope, %Payment{} = payment) do
    validate_payment(payment, scope, :accepted)
  end

  @doc """
  Reject a payment with a required reason (owner action).

  ## Examples

      iex> reject_payment(scope, payment, "Invalid amount")
      {:ok, %Payment{}}

  """
  def reject_payment(%Scope{} = scope, %Payment{} = payment, reason) do
    validate_payment(payment, scope, :rejected, reason)
  end

  # Helper function to validate and update payment status with optional rejection reason.
  defp validate_payment(payment, scope, status, reason \\ nil) do
    if receiver?(payment, scope.user) do
      with {:ok, payment = %Payment{}} <-
             payment
             |> Payment.validation_changeset(%{status: status, rejection_reason: reason})
             |> Repo.update() do
        broadcast_payment(scope, {:updated, payment})
        {:ok, payment}
      end
    else
      {:error, :unauthorized}
    end
  end

  # Check if the user is the receiver (owner of the contract) of the payment.
  defp receiver?(payment, user) do
    Repo.preload(payment, :contract).contract.user_id == user.id
  end

  @doc """
  Calculate total accepted payments for a specific month.

  ## Examples

      iex> total_accepted_for_month(scope, contract_id, payment_number)
      Decimal.new("100.00")

  """
  def total_accepted_for_month(%Scope{} = scope, contract_id, payment_number) do
    Payment
    |> where([p], p.contract_id == ^contract_id)
    |> where([p], p.user_id == ^scope.user.id)
    |> where([p], p.payment_number == ^payment_number)
    |> where([p], p.status == :accepted)
    |> select([p], sum(p.amount))
    |> Repo.one() || @decimal_zero
  end

  @doc """
  Calculate total rent collected for all payment periods with due dates in the past.

  This function determines which payment numbers have due dates that have already
  passed and sums all accepted payments for those periods.

  ## Examples

      iex> total_rent_collected(scope, contract, ~D[2026-02-15])
      Decimal.new("1500.00")
  """
  def total_rent_collected(%Scope{} = scope, %Contract{} = contract, today \\ Date.utc_today()) do
    payment_numbers = get_past_payment_numbers(contract, today)

    if payment_numbers == [] do
      @decimal_zero
    else
      Payment
      |> join(:inner, [p], c in assoc(p, :contract))
      |> where([p], p.contract_id == ^contract.id)
      |> where([p, c], c.user_id == ^scope.user.id)
      |> where([p], p.payment_number in ^payment_numbers)
      |> where([p], p.status == :accepted)
      |> select([p], sum(p.amount))
      |> Repo.one() || @decimal_zero
    end
  end

  defp get_past_payment_numbers(%Contract{} = contract, today) do
    current = Vivvo.Contracts.get_current_payment_number(contract)
    current_due_date = Vivvo.Contracts.calculate_due_date(contract, current)

    range =
      cond do
        Date.compare(current_due_date, today) in [:lt, :eq] -> 0..current
        current - 1 >= 0 -> 0..(current - 1)
        # No past payments
        true -> []
      end

    Enum.to_list(range)
  end

  @doc """
  Calculate total pending payments for a specific month.

  ## Examples

      iex> total_pending_for_month(scope, contract_id, payment_number)
      Decimal.new("100.00")

  """
  def total_pending_for_month(%Scope{} = scope, contract_id, payment_number) do
    Payment
    |> where([p], p.contract_id == ^contract_id)
    |> where([p], p.user_id == ^scope.user.id)
    |> where([p], p.payment_number == ^payment_number)
    |> where([p], p.status == :pending)
    |> select([p], sum(p.amount))
    |> Repo.one() || @decimal_zero
  end

  @doc """
  Check if a month is fully paid (sum >= rent).

  ## Examples

      iex> month_fully_paid?(scope, contract, payment_number)
      true

  """
  def month_fully_paid?(%Scope{} = scope, contract, payment_number) do
    total = total_accepted_for_month(scope, contract.id, payment_number)
    Decimal.compare(total, contract.rent) != :lt
  end

  @doc """
  Get the status of a month: :paid, :partial, or :unpaid.

  ## Examples

      iex> get_month_status(scope, contract, payment_number)
      :paid

  """
  def get_month_status(%Scope{} = scope, contract, payment_number) do
    total = total_accepted_for_month(scope, contract.id, payment_number)
    rent = contract.rent

    cond do
      Decimal.compare(total, rent) != :lt -> :paid
      Decimal.compare(total, @decimal_zero) == :gt -> :partial
      true -> :unpaid
    end
  end

  # Dashboard Analytics Functions

  @doc """
  Get expected income for a specific month based on active contracts.

  ## Examples

      iex> expected_income_for_month(scope, ~D[2026-02-01])
      Decimal.new("2500.00")

  """
  def expected_income_for_month(%Scope{} = scope, date) do
    start_of_month = Date.beginning_of_month(date)
    end_of_month = Date.end_of_month(date)

    Contract
    |> where([c], c.user_id == ^scope.user.id)
    |> where([c], c.archived == false)
    |> where([c], c.start_date <= ^end_of_month)
    |> where([c], c.end_date >= ^start_of_month)
    |> select([c], sum(c.rent))
    |> Repo.one() || @decimal_zero
  end

  @doc """
  Get received (accepted) income for a specific month.

  Note: This function calculates income based on the payment's target period
  (determined by payment_number and contract start_date), not when the payment
  was submitted (inserted_at). This ensures late payments are counted in the
  correct period (e.g., February rent paid in March counts as February income).

  ## Examples

      iex> received_income_for_month(scope, ~D[2026-02-01])
      Decimal.new("2000.00")

  """
  def received_income_for_month(%Scope{} = scope, date) do
    month_start = Date.beginning_of_month(date)

    scope
    |> received_income_by_month()
    |> Map.get(month_start, @decimal_zero)
  end

  @doc """
  Get pending payments that need validation with optional pagination.

  ## Options
    * `:page` - Page number (default: 1)
    * `:per_page` - Items per page (default: 20)

  ## Examples

      iex> pending_payments_for_validation(scope)
      [%Payment{}, ...]

      iex> pending_payments_for_validation(scope, page: 1, per_page: 10)
      [%Payment{}, ...]

  """
  def pending_payments_for_validation(%Scope{} = scope, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    Payment
    |> join(:inner, [p], c in assoc(p, :contract))
    |> join(:inner, [p, c], t in assoc(c, :tenant))
    |> join(:inner, [p, c], prop in assoc(c, :property))
    |> where([p, c], c.user_id == ^scope.user.id)
    |> where([p], p.status == :pending)
    |> order_by([p], desc: p.inserted_at)
    |> preload([p, c, t, prop], contract: {c, tenant: t, property: prop})
    |> paginate(page, per_page)
    |> Repo.all()
  end

  defp paginate(query, page, per_page) do
    offset = (page - 1) * per_page

    query
    |> limit(^per_page)
    |> offset(^offset)
  end

  @doc """
  Get collection rate (percentage of expected income collected) for a month.

  ## Examples

      iex> collection_rate_for_month(scope, ~D[2026-02-01])
      85.5

  """
  def collection_rate_for_month(%Scope{} = scope, date) do
    expected = expected_income_for_month(scope, date)
    received = received_income_for_month(scope, date)

    if Decimal.compare(expected, @decimal_zero) == :gt do
      Decimal.to_float(Decimal.mult(Decimal.div(received, expected), Decimal.new(100)))
    else
      0.0
    end
  end

  @doc """
  Get outstanding balance (expected - received) for a month.

  ## Examples

      iex> outstanding_balance_for_month(scope, ~D[2026-02-01])
      Decimal.new("500.00")

  """
  def outstanding_balance_for_month(%Scope{} = scope, date) do
    expected = expected_income_for_month(scope, date)
    received = received_income_for_month(scope, date)
    Decimal.sub(expected, received)
  end

  @doc """
  Get received income grouped by target month.

  Returns a map where keys are month start dates and values are total received amounts.
  Uses payment_number instead of inserted_at to determine the target month.

  ## Examples

      iex> received_income_by_month(scope)
      %{~D[2026-01-01] => Decimal.new("2500"), ...}

  """
  def received_income_by_month(%Scope{} = scope) do
    payments =
      from(p in Payment,
        join: c in assoc(p, :contract),
        where: c.user_id == ^scope.user.id,
        where: p.status == :accepted,
        preload: [:contract]
      )
      |> Repo.all()

    payments
    |> Enum.group_by(fn payment ->
      payment_target_month(payment.contract, payment.payment_number)
    end)
    |> Enum.map(fn {month_date, payments} ->
      total =
        Enum.reduce(payments, @decimal_zero, fn p, acc ->
          Decimal.add(acc, p.amount)
        end)

      {month_date, total}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Calculate the target month for a payment based on payment_number and contract start_date.

  This function is used to determine which month a payment belongs to, regardless of
  when the payment was actually submitted. For example, payment_number 1 is for the
  first month of the contract, payment_number 2 is for the second month, etc.

  ## Examples

      iex> contract = %Contract{start_date: ~D[2026-01-15]}
      iex> payment_target_month(contract, 1)
      ~D[2026-01-01]

      iex> contract = %Contract{start_date: ~D[2026-01-15]}
      iex> payment_target_month(contract, 2)
      ~D[2026-02-01]

  """
  def payment_target_month(contract, payment_number) do
    month_offset = payment_number - 1
    year = contract.start_date.year + div(contract.start_date.month + month_offset - 1, 12)
    month = rem(contract.start_date.month + month_offset - 1, 12) + 1
    Date.new!(year, month, 1)
  end

  @doc """
  Get income trend over the last N months.

  Returns a list of {month_date, expected, received} tuples.

  ## Examples

      iex> income_trend(scope, 6)
      [{~D[2026-01-01], Decimal.new("2500"), Decimal.new("2400")}, ...]

  """
  def income_trend(%Scope{} = scope, months_count \\ 6) do
    today = Date.utc_today()
    received_by_month = received_income_by_month(scope)

    for i <- (months_count - 1)..0//-1 do
      month_date = Date.add(today, -i * 30)
      month_start = Date.beginning_of_month(month_date)
      expected = expected_income_for_month(scope, month_date)
      received = Map.get(received_by_month, month_start, @decimal_zero)
      {month_start, expected, received}
    end
  end

  @doc """
  Get outstanding balances grouped by aging buckets.

  Returns a map with:
  - current: amount not yet due
  - days_0_7: 0-7 days overdue
  - days_8_30: 8-30 days overdue
  - days_31_plus: 31+ days overdue

  ## Examples

      iex> outstanding_aging(scope)
      %{current: Decimal.new("1000"), days_0_7: Decimal.new("500"), ...}

  """
  def outstanding_aging(%Scope{} = scope) do
    today = Date.utc_today()

    active_contracts =
      Contract
      |> where([c], c.user_id == ^scope.user.id)
      |> where([c], c.archived == false)
      |> where([c], c.start_date <= ^today)
      |> where([c], c.end_date >= ^today)
      |> preload([:payments])
      |> Repo.all()

    Enum.reduce(
      active_contracts,
      %{
        current: @decimal_zero,
        days_0_7: @decimal_zero,
        days_8_30: @decimal_zero,
        days_31_plus: @decimal_zero
      },
      fn contract, acc ->
        current_payment_num = Vivvo.Contracts.get_current_payment_number(contract)
        process_contract_outstanding(scope, contract, current_payment_num, today, acc)
      end
    )
  end

  defp process_contract_outstanding(_scope, _contract, current_payment_num, _today, acc)
       when current_payment_num <= 0 do
    acc
  end

  defp process_contract_outstanding(scope, contract, current_payment_num, today, acc) do
    Enum.reduce(1..current_payment_num, acc, fn payment_num, acc_inner ->
      add_outstanding_to_bucket(scope, contract, payment_num, today, acc_inner)
    end)
  end

  defp add_outstanding_to_bucket(scope, contract, payment_num, today, acc) do
    rent = contract.rent
    paid = total_accepted_for_month(scope, contract.id, payment_num)
    due_date = Vivvo.Contracts.calculate_due_date(contract, payment_num)
    outstanding = Decimal.sub(rent, paid)

    case Decimal.compare(outstanding, @decimal_zero) do
      :gt -> update_bucket_for_outstanding(acc, outstanding, today, due_date)
      _ -> acc
    end
  end

  defp update_bucket_for_outstanding(acc, outstanding, today, due_date) do
    days_overdue = Date.diff(today, due_date)
    bucket = overdue_bucket(days_overdue)
    Map.update!(acc, bucket, &Decimal.add(&1, outstanding))
  end

  defp overdue_bucket(days_overdue) when days_overdue <= 0, do: :current
  defp overdue_bucket(days_overdue) when days_overdue <= 7, do: :days_0_7
  defp overdue_bucket(days_overdue) when days_overdue <= 30, do: :days_8_30
  defp overdue_bucket(_days_overdue), do: :days_31_plus

  @doc """
  Get total outstanding balance across all contracts.

  ## Examples

      iex> total_outstanding(scope)
      Decimal.new("3000.00")

  """
  def total_outstanding(%Scope{} = scope) do
    aging = outstanding_aging(scope)

    Enum.reduce([:current, :days_0_7, :days_8_30, :days_31_plus], @decimal_zero, fn bucket, acc ->
      Decimal.add(acc, Map.get(aging, bucket))
    end)
  end

  @doc """
  Get payment counts by status for quick stats.

  ## Examples

      iex> payment_counts_by_status(scope)
      %{pending: 5, accepted: 45, rejected: 2}

  """
  def payment_counts_by_status(%Scope{} = scope) do
    Payment
    |> join(:inner, [p], c in assoc(p, :contract))
    |> where([p, c], c.user_id == ^scope.user.id)
    |> group_by([p], p.status)
    |> select([p], {p.status, count(p.id)})
    |> Repo.all()
    |> Enum.into(%{pending: 0, accepted: 0, rejected: 0})
  end
end
