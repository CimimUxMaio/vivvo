defmodule Vivvo.Repo.Migrations.CreatePayments do
  use Ecto.Migration

  def change do
    create table(:payments) do
      add :payment_number, :integer
      add :amount, :decimal
      add :notes, :text
      add :status, :string
      add :contract_id, references(:contracts, on_delete: :nothing)
      add :user_id, references(:users, type: :id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:payments, [:user_id])

    create index(:payments, [:contract_id])
  end
end
