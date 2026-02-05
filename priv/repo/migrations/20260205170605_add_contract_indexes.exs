defmodule Vivvo.Repo.Migrations.AddContractIndexes do
  use Ecto.Migration

  def change do
    # Add composite index for faster property contract lookups
    create index(:contracts, [:property_id, :archived])
  end
end
