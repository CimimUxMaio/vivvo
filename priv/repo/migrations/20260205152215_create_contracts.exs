defmodule Vivvo.Repo.Migrations.CreateContracts do
  use Ecto.Migration

  def change do
    create table(:contracts) do
      add :start_date, :date, null: false
      add :end_date, :date, null: false
      add :expiration_day, :integer, null: false
      add :notes, :text, null: false, default: ""
      add :rent, :decimal, null: false

      add :tenant_id, references(:users, on_delete: :nothing), null: false
      add :property_id, references(:properties, on_delete: :nothing), null: false
      add :user_id, references(:users, type: :id, on_delete: :delete_all), null: false

      add :archived, :boolean, default: false, null: false
      add :archived_by_id, references(:users, type: :id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:contracts, [:user_id])
    create index(:contracts, [:tenant_id])
    create index(:contracts, [:property_id])
    create index(:contracts, [:archived])
    create index(:contracts, [:archived_by_id])
  end
end
