defmodule Vivvo.Payments.Payment do
  @moduledoc """
  Schema for payments between tenants and owners.

  Supports two types:
  - `:rent` — periodic rental payments tied to a contract payment number
  - `:other` — miscellaneous payments (deposits, maintenance, services, etc.)
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Vivvo.Accounts.User
  alias Vivvo.Contracts.Contract
  alias Vivvo.Files.File

  schema "payments" do
    field :payment_number, :integer
    field :amount, :decimal
    field :notes, :string
    field :status, Ecto.Enum, values: [:pending, :accepted, :rejected], default: :pending
    field :rejection_reason, :string
    field :type, Ecto.Enum, values: [:rent, :other], default: :rent
    field :category, Ecto.Enum, values: [:services, :deposit, :maintenance, :other]

    belongs_to :contract, Contract
    belongs_to :user, User
    has_many :files, File, on_delete: :delete_all

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
      :contract_id,
      :type,
      :category
    ])
    |> cast_assoc(:files)
    |> validate_required([:amount, :contract_id])
    |> validate_number(:amount, greater_than: 0)
    |> maybe_validate_payment_number()
    |> maybe_validate_category()
    |> validate_amount_within_allowance(remaining_allowance)
    |> put_change(:user_id, user_scope.user.id)
  end

  # Conditionally validates payment_number based on type
  # - If type is :rent, payment_number is required and must be > 0
  # - If type is :other, payment_number is set to nil
  defp maybe_validate_payment_number(changeset) do
    type = get_field(changeset, :type)

    if type == :rent do
      changeset
      |> validate_required([:payment_number])
      |> validate_number(:payment_number, greater_than: 0)
    else
      # For non-rent payments (miscellaneous), payment_number is not required
      put_change(changeset, :payment_number, nil)
    end
  end

  # Conditionally validates category based on type
  # - If type is :rent, category is set to nil
  # - If type is :other, category is required (Ecto.Enum validates valid values)
  defp maybe_validate_category(changeset) do
    type = get_field(changeset, :type)

    if type == :rent do
      put_change(changeset, :category, nil)
    else
      validate_required(changeset, [:category])
    end
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
    # This validation only applies to rent payments
    if get_field(changeset, :type) != :rent do
      changeset
    else
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
