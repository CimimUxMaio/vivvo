defmodule Vivvo.Repo.Migrations.AddRejectionReasonToPayments do
  use Ecto.Migration

  def change do
    alter table(:payments) do
      add :rejection_reason, :string
    end
  end
end
