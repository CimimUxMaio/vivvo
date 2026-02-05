defmodule Vivvo.Repo.Migrations.CreateProperties do
  use Ecto.Migration

  def change do
    create table(:properties) do
      add :name, :string, null: false
      add :address, :string, null: false
      add :area, :integer, null: true
      add :rooms, :integer, null: true
      add :notes, :text
      add :user_id, references(:users, type: :id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:properties, [:user_id])
  end
end
