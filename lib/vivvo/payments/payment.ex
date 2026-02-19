defmodule Vivvo.Payments.Payment do
  @moduledoc """
  Schema for rental payments between tenants and owners.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Vivvo.Accounts.User
  alias Vivvo.Contracts.Contract

  schema "payments" do
    field :payment_number, :integer
    field :amount, :decimal
    field :notes, :string
    field :status, Ecto.Enum, values: [:pending, :accepted, :rejected], default: :pending
    field :rejection_reason, :string

    belongs_to :contract, Contract
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(payment, attrs, user_scope, opts \\ []) do
    remaining_allowance = Keyword.get(opts, :remaining_allowance)

    payment
    |> cast(attrs, [
      :payment_number,
      :amount,
      :notes,
      :status,
      :rejection_reason,
      :contract_id
    ])
    |> validate_required([:payment_number, :amount, :contract_id])
    |> validate_number(:amount, greater_than: 0)
    |> validate_number(:payment_number, greater_than: 0)
    |> validate_amount_within_allowance(remaining_allowance)
    |> put_change(:user_id, user_scope.user.id)
  end

  @doc false
  def validation_changeset(payment, attrs) do
    payment
    |> cast(attrs, [
      :status,
      :rejection_reason
    ])
    |> validate_inclusion(:status, [:accepted, :rejected])
    |> validate_rejection_reason()
  end

  defp validate_amount_within_allowance(changeset, nil), do: changeset

  defp validate_amount_within_allowance(changeset, remaining_allowance) do
    amount = get_field(changeset, :amount)

    if amount && Decimal.compare(amount, remaining_allowance) == :gt do
      add_error(
        changeset,
        :amount,
        "exceeds remaining allowance of #{format_currency(remaining_allowance)} for this month"
      )
    else
      changeset
    end
  end

  defp format_currency(amount) do
    "$#{Decimal.round(amount, 2) |> Decimal.to_string()}"
  end

  defp validate_rejection_reason(changeset) do
    status = get_field(changeset, :status)
    rejection_reason = get_field(changeset, :rejection_reason)

    if status == :rejected and is_nil(rejection_reason) do
      add_error(changeset, :rejection_reason, "is required when rejecting a payment")
    else
      changeset
    end
  end
end
