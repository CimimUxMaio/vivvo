defmodule Vivvo.Repo.Migrations.AddCategoryToPayments do
  use Ecto.Migration

  def change do
    alter table(:payments) do
      add :category, :string, null: true
    end

    # Create index for efficient filtering by type and category
    create index(:payments, [:type, :category])
  end
end
