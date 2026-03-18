defmodule Vivvo.Contracts.Contract do
  @moduledoc """
  Schema for rental contracts between tenants and properties.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Vivvo.Accounts.User
  alias Vivvo.Contracts.RentPeriod
  alias Vivvo.Payments.Payment
  alias Vivvo.Properties.Property

  # Payment due day constraints
  @min_expiration_day 1
  @max_expiration_day 20

  schema "contracts" do
    field :start_date, :date
    field :end_date, :date
    field :expiration_day, :integer
    field :notes, :string, default: ""

    field :rent_period_duration, :integer
    field :index_type, Ecto.Enum, values: [:ipc, :icl]

    field :rent, :decimal, virtual: true

    belongs_to :tenant, User
    belongs_to :property, Property
    belongs_to :user, User

    field :archived, :boolean, default: false
    belongs_to :archived_by, User

    has_many :payments, Payment
    has_many :rent_periods, RentPeriod

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
      :rent_period_duration,
      :index_type,
      :property_id,
      :tenant_id,
      :rent
    ])
    |> validate_required([
      :start_date,
      :end_date,
      :expiration_day,
      :property_id,
      :tenant_id,
      :rent
    ])
    |> validate_number(:expiration_day,
      greater_than_or_equal_to: @min_expiration_day,
      less_than_or_equal_to: @max_expiration_day
    )
    |> validate_number(:rent_period_duration,
      greater_than: 0,
      message: "must be greater than 0"
    )
    |> validate_number(:rent, greater_than: 0)
    |> validate_rent_decimal_places()
    |> validate_index_fields()
    |> validate_end_date_after_start_date()
    |> put_change(:user_id, user_scope.user.id)
  end

  @doc """
  Returns a changeset for creating a new contract.

  This changeset includes all base validations from `changeset/3` plus
  additional validations that require database access:
  - Validates start_date is not in the past
  - Validates no overlapping contracts exist for the property

  ## Options

    * `:past_start_date?` - When set to `true`, allows creating contracts
      with start dates in the past. Defaults to `false`.
    * `:today` - The reference date to use for determining "today".
      Defaults to `Date.utc_today()`. Useful for testing.

  """
  def creation_changeset(contract, attrs, user_scope, opts \\ []) do
    today = Keyword.get(opts, :today, Date.utc_today())
    past_start_date? = Keyword.get(opts, :past_start_date?, false)

    contract
    |> changeset(attrs, user_scope)
    |> validate_start_date_not_in_past(past_start_date?, today)
    |> validate_no_overlapping_contracts(user_scope)
  end

  defp validate_start_date_not_in_past(changeset, true, _today) do
    changeset
  end

  defp validate_start_date_not_in_past(changeset, false, today) do
    start_date = get_field(changeset, :start_date)

    if start_date && Date.compare(start_date, today) == :lt do
      add_error(changeset, :start_date, "cannot be in the past")
    else
      changeset
    end
  end

  defp validate_no_overlapping_contracts(changeset, user_scope) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)
    property_id = get_field(changeset, :property_id)

    if start_date && end_date && property_id do
      case Vivvo.Contracts.find_overlapping_contract(
             user_scope,
             property_id,
             start_date,
             end_date
           ) do
        nil ->
          changeset

        overlapping_contract ->
          add_error(changeset, :start_date, "overlaps with existing contract", %{
            existing_contract_start: overlapping_contract.start_date,
            existing_contract_end: overlapping_contract.end_date
          })
      end
    else
      changeset
    end
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

  defp validate_index_fields(changeset) do
    index_type = get_field(changeset, :index_type)
    rent_period_duration = get_field(changeset, :rent_period_duration)

    cond do
      not is_nil(index_type) and is_nil(rent_period_duration) ->
        add_error(changeset, :rent_period_duration, "is required when index type is set")

      is_nil(index_type) and not is_nil(rent_period_duration) ->
        add_error(changeset, :index_type, "is required when rent period duration is set")

      true ->
        changeset
    end
  end

  defp validate_rent_decimal_places(changeset) do
    rent = get_field(changeset, :rent)

    if rent && decimal_places(rent) > 2 do
      add_error(changeset, :rent, "must have at most 2 decimal places")
    else
      changeset
    end
  end

  defp decimal_places(rent) do
    rent
    |> Decimal.to_string(:normal)
    |> String.split(".")
    |> case do
      [_whole] -> 0
      [_whole, fraction] -> String.length(fraction)
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
