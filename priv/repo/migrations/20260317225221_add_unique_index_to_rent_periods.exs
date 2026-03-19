defmodule Vivvo.Repo.Migrations.AddUniqueIndexToRentPeriods do
  use Ecto.Migration

  @doc """
  Adds a unique index on [:contract_id, :start_date] to prevent duplicate rent periods.
  This addresses a TOCTOU race condition where concurrent creation attempts could
  create duplicate periods for the same contract and start date.
  """
  def change do
    create unique_index(:rent_periods, [:contract_id, :start_date])
  end
end
