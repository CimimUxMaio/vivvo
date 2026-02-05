defmodule Vivvo.Contracts.Contract do
  @moduledoc """
  Schema for rental contracts between tenants and properties.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Vivvo.Accounts.User
  alias Vivvo.Payments.Payment
  alias Vivvo.Properties.Property

  schema "contracts" do
    field :rent, :decimal
    field :start_date, :date
    field :end_date, :date
    field :expiration_day, :integer
    field :notes, :string, default: ""

    belongs_to :tenant, User
    belongs_to :property, Property
    belongs_to :user, User

    field :archived, :boolean, default: false
    belongs_to :archived_by, User

    has_many :payments, Payment

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(contract, attrs, user_scope) do
    contract
    |> cast(attrs, [
      :start_date,
      :end_date,
      :expiration_day,
      :notes,
      :rent,
      :property_id,
      :tenant_id
    ])
    |> validate_required([
      :start_date,
      :end_date,
      :expiration_day,
      :rent,
      :property_id,
      :tenant_id
    ])
    |> validate_number(:expiration_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 20)
    |> validate_number(:rent, greater_than: 0)
    |> validate_end_date_after_start_date()
    |> put_change(:user_id, user_scope.user.id)
  end

  defp validate_end_date_after_start_date(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)

    if start_date && end_date && Date.compare(end_date, start_date) != :gt do
      add_error(changeset, :end_date, "must be after start date")
    else
      changeset
    end
  end

  @doc """
  Returns a changeset for archiving a contract.

  Sets the `archived` field to true and records the user who archived it.
  """
  def archive_changeset(contract, user_scope) do
    contract
    |> change(%{
      archived: true,
      archived_by_id: user_scope.user.id
    })
  end
end
