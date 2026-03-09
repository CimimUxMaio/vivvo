defmodule Vivvo.Repo.Migrations.AddRentPeriodFieldsToContracts do
  use Ecto.Migration

  def change do
    alter table(:contracts) do
      remove :rent
      add :rent_period_duration, :integer, null: true
      add :index_type, :string, null: true
    end
  end
end
