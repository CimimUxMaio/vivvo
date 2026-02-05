defmodule Vivvo.Repo.Migrations.AddArchivingToProperties do
  use Ecto.Migration

  def change do
    alter table(:properties) do
      add :archived, :boolean, default: false, null: false
      add :archived_by_id, references(:users, type: :id, on_delete: :nothing)
    end

    create index(:properties, [:archived])
    create index(:properties, [:archived_by_id])
  end
end
