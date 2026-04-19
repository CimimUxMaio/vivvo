defmodule Vivvo.Repo.Migrations.AddPaymentInfoToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :cbu, :string
      add :alias, :string
      add :account_name, :string
    end
  end
end
