defmodule Vivvo.Repo.Migrations.AddPaymentCompositeIndexes do
  use Ecto.Migration

  def change do
    # Index for total_accepted_for_month queries
    create index(:payments, [:contract_id, :payment_number])

    # Index for pending_payments_for_validation queries
    create index(:payments, [:contract_id, :status])

    # Index for received_income_for_month queries
    create index(:payments, [:user_id, :inserted_at])
  end
end
