defmodule Vivvo.Contracts.RentPeriod do
  @moduledoc """
  Schema for rent periods that track historical rent values over time.

  Each contract has one or more rent periods. The initial period covers
  the base rent, and subsequent periods are created when rent is updated
  based on index adjustments (CPI or fixed percentage).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Vivvo.Contracts.Contract

  schema "rent_periods" do
    field :value, :decimal
    field :index_type, Ecto.Enum, values: [:cpi, :fixed_percentage]
    field :index_value, :decimal
    field :start_date, :date
    field :end_date, :date

    belongs_to :contract, Contract
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(rent_period, attrs) do
    rent_period
    |> cast(attrs, [
      :value,
      :index_type,
      :index_value,
      :start_date,
      :end_date,
      :contract_id
    ])
    |> validate_required([
      :value,
      :start_date,
      :end_date
    ])
    |> validate_number(:value, greater_than: 0)
    |> validate_end_date_after_start_date()
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
end
