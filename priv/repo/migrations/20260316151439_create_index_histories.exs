defmodule Vivvo.Repo.Migrations.CreateIndexHistories do
  use Ecto.Migration

  def change do
    create table(:index_histories) do
      add :type, :string, null: false
      add :value, :decimal, null: false
      add :date, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:index_histories, [:type, :date])
    create index(:index_histories, [:type])
    create index(:index_histories, [:date])
  end
end
