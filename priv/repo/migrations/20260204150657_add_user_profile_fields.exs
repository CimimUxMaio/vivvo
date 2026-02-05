defmodule Vivvo.Repo.Migrations.AddUserProfileFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :first_name, :string
      add :last_name, :string
      add :phone_number, :string
      add :preferred_roles, {:array, :string}, default: []
      add :current_role, :string
    end

    # Update existing users with default values (use quotes to escape reserved keyword)
    execute(
      """
      UPDATE users
      SET first_name = 'User',
          last_name = 'Name',
          phone_number = '0000000000',
          preferred_roles = ARRAY['owner']::text[],
          "current_role" = 'owner'
      WHERE first_name IS NULL
      """,
      ""
    )

    # Now make the fields NOT NULL
    alter table(:users) do
      modify :first_name, :string, null: false
      modify :last_name, :string, null: false
      modify :phone_number, :string, null: false
      modify :preferred_roles, {:array, :string}, null: false, default: []
      modify :current_role, :string, null: false
    end
  end
end
