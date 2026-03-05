defmodule Vivvo.Repo.Migrations.CreateFiles do
  use Ecto.Migration

  def change do
    create table(:files) do
      add :label, :string, null: false
      add :path, :string, null: false
      add :payment_id, references(:payments, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:files, [:payment_id])
    create index(:files, [:user_id])
  end
end
