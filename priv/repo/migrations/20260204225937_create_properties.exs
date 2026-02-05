defmodule Vivvo.Repo.Migrations.CreateProperties do
  use Ecto.Migration

  def change do
    create table(:properties) do
      add :name, :string
      add :address, :string
      add :area, :integer, null: true
      add :rooms, :integer, null: true
      add :notes, :text
      add :user_id, references(:users, type: :id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:properties, [:user_id])
  end
end
