defmodule Vivvo.Payments do
  @moduledoc """
  The Payments context.
  """

  import Ecto.Query, warn: false
  alias Vivvo.Repo

  alias Vivvo.Accounts.Scope
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
    Repo.get_by(Payment, id: id, user_id: scope.user.id)
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
    Repo.get_by!(Payment, id: id, user_id: scope.user.id)
  end

  @doc """
  Creates a payment.

  ## Examples

      iex> create_payment(scope, %{field: value})
      {:ok, %Payment{}}

      iex> create_payment(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_payment(%Scope{} = scope, attrs) do
    with {:ok, payment = %Payment{}} <-
           %Payment{}
           |> Payment.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_payment(scope, {:created, payment})
      {:ok, payment}
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
  def update_payment(%Scope{} = scope, %Payment{} = payment, attrs) do
    true = payment.user_id == scope.user.id

    with {:ok, payment = %Payment{}} <-
           payment
           |> Payment.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_payment(scope, {:updated, payment})
      {:ok, payment}
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
    true = payment.user_id == scope.user.id

    with {:ok, payment = %Payment{}} <-
           Repo.delete(payment) do
      broadcast_payment(scope, {:deleted, payment})
      {:ok, payment}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking payment changes.

  ## Examples

      iex> change_payment(scope, payment)
      %Ecto.Changeset{data: %Payment{}}

  """
  def change_payment(%Scope{} = scope, %Payment{} = payment, attrs \\ %{}) do
    true = payment.user_id == scope.user.id

    Payment.changeset(payment, attrs, scope)
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
    true = payment.user_id == scope.user.id

    with {:ok, payment = %Payment{}} <-
           payment
           |> Payment.changeset(%{status: :accepted, rejection_reason: nil}, scope)
           |> Repo.update() do
      broadcast_payment(scope, {:updated, payment})
      {:ok, payment}
    end
  end

  @doc """
  Reject a payment with a required reason (owner action).

  ## Examples

      iex> reject_payment(scope, payment, "Invalid amount")
      {:ok, %Payment{}}

  """
  def reject_payment(%Scope{} = scope, %Payment{} = payment, reason) do
    true = payment.user_id == scope.user.id

    with {:ok, payment = %Payment{}} <-
           payment
           |> Payment.changeset(%{status: :rejected, rejection_reason: reason}, scope)
           |> Repo.update() do
      broadcast_payment(scope, {:updated, payment})
      {:ok, payment}
    end
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
end
