defmodule Vivvo.Repo.Migrations.AddTypeToPayments do
  use Ecto.Migration

  def up do
    # Add type column with default "rent" for existing records
    alter table(:payments) do
      add :type, :string, null: false, default: "rent"
    end

    # Create index on type column for efficient filtering
    create index(:payments, [:type])
    create index(:payments, [:type, :status])
    create index(:payments, [:type, :payment_number])
  end

  def down do
    drop index(:payments, [:type, :payment_number])
    drop index(:payments, [:type, :status])
    drop index(:payments, [:type])

    alter table(:payments) do
      remove :type
    end
  end
end
