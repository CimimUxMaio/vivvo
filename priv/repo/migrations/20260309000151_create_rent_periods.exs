defmodule Vivvo.Repo.Migrations.CreateRentPeriods do
  use Ecto.Migration

  def change do
    create table(:rent_periods) do
      add :value, :decimal, null: false
      add :index_type, :string, null: true
      add :index_value, :decimal, null: true
      add :start_date, :date, null: false
      add :end_date, :date, null: false
      add :contract_id, references(:contracts, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:rent_periods, [:contract_id])
    create index(:rent_periods, [:contract_id, :start_date, :end_date])
    create index(:rent_periods, [:contract_id, :end_date])
    create index(:contracts, [:archived, :end_date])
    create index(:contracts, [:index_type, :rent_period_duration])
  end
end
