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
  def changeset(payment, attrs, user_scope) do
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
    |> validate_rejection_reason()
    |> put_change(:user_id, user_scope.user.id)
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
