defmodule Vivvo.Contracts.ContractTest do
  use Vivvo.DataCase, async: true

  alias Vivvo.Contracts.Contract
  import Vivvo.AccountsFixtures, only: [user_scope_fixture: 0]

  describe "changeset/3" do
    setup do
      scope = user_scope_fixture()
      {:ok, scope: scope}
    end

    test "validates end_date must be after start_date", %{scope: scope} do
      attrs = %{
        start_date: ~D[2026-02-10],
        end_date: ~D[2026-02-05],
        expiration_day: 5,
        rent: "100.00",
        property_id: 1,
        tenant_id: 1
      }

      changeset = Contract.changeset(%Contract{}, attrs, scope)
      assert %{end_date: ["must be after start date"]} = errors_on(changeset)
    end

    test "validates end_date equal to start_date is invalid", %{scope: scope} do
      attrs = %{
        start_date: ~D[2026-02-10],
        end_date: ~D[2026-02-10],
        expiration_day: 5,
        rent: "100.00",
        property_id: 1,
        tenant_id: 1
      }

      changeset = Contract.changeset(%Contract{}, attrs, scope)
      assert %{end_date: ["must be after start date"]} = errors_on(changeset)
    end

    test "validates expiration_day must be between 1 and 20 - value 0", %{scope: scope} do
      attrs = %{
        start_date: ~D[2026-02-05],
        end_date: ~D[2026-02-10],
        expiration_day: 0,
        rent: "100.00",
        property_id: 1,
        tenant_id: 1
      }

      changeset = Contract.changeset(%Contract{}, attrs, scope)
      assert %{expiration_day: ["must be greater than or equal to 1"]} = errors_on(changeset)
    end

    test "validates expiration_day must be between 1 and 20 - value 21", %{scope: scope} do
      attrs = %{
        start_date: ~D[2026-02-05],
        end_date: ~D[2026-02-10],
        expiration_day: 21,
        rent: "100.00",
        property_id: 1,
        tenant_id: 1
      }

      changeset = Contract.changeset(%Contract{}, attrs, scope)
      assert %{expiration_day: ["must be less than or equal to 20"]} = errors_on(changeset)
    end

    test "validates expiration_day boundary value 1 is valid", %{scope: scope} do
      attrs = %{
        start_date: ~D[2026-02-05],
        end_date: ~D[2026-02-10],
        expiration_day: 1,
        rent: "100.00",
        property_id: 1,
        tenant_id: 1
      }

      changeset = Contract.changeset(%Contract{}, attrs, scope)
      refute Map.has_key?(errors_on(changeset), :expiration_day)
    end

    test "validates expiration_day boundary value 20 is valid", %{scope: scope} do
      attrs = %{
        start_date: ~D[2026-02-05],
        end_date: ~D[2026-02-10],
        expiration_day: 20,
        rent: "100.00",
        property_id: 1,
        tenant_id: 1
      }

      changeset = Contract.changeset(%Contract{}, attrs, scope)
      refute Map.has_key?(errors_on(changeset), :expiration_day)
    end

    test "validates rent must be greater than 0 - value 0", %{scope: scope} do
      attrs = %{
        start_date: ~D[2026-02-05],
        end_date: ~D[2026-02-10],
        expiration_day: 5,
        rent: "0",
        property_id: 1,
        tenant_id: 1
      }

      changeset = Contract.changeset(%Contract{}, attrs, scope)
      assert %{rent: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "validates rent must be greater than 0 - negative value", %{scope: scope} do
      attrs = %{
        start_date: ~D[2026-02-05],
        end_date: ~D[2026-02-10],
        expiration_day: 5,
        rent: "-100.00",
        property_id: 1,
        tenant_id: 1
      }

      changeset = Contract.changeset(%Contract{}, attrs, scope)
      assert %{rent: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "validates all required fields", %{scope: scope} do
      changeset = Contract.changeset(%Contract{}, %{}, scope)

      assert %{
               start_date: ["can't be blank"],
               end_date: ["can't be blank"],
               expiration_day: ["can't be blank"],
               rent: ["can't be blank"],
               property_id: ["can't be blank"],
               tenant_id: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "valid changeset with all required fields", %{scope: scope} do
      attrs = %{
        start_date: ~D[2026-02-05],
        end_date: ~D[2026-02-10],
        expiration_day: 5,
        rent: "100.00",
        property_id: 1,
        tenant_id: 1
      }

      changeset = Contract.changeset(%Contract{}, attrs, scope)
      assert changeset.valid?
    end

    test "sets user_id from scope", %{scope: scope} do
      attrs = %{
        start_date: ~D[2026-02-05],
        end_date: ~D[2026-02-10],
        expiration_day: 5,
        rent: "100.00",
        property_id: 1,
        tenant_id: 1
      }

      changeset = Contract.changeset(%Contract{}, attrs, scope)
      assert Ecto.Changeset.get_change(changeset, :user_id) == scope.user.id
    end
  end

  describe "archive_changeset/2" do
    test "sets archived to true" do
      scope = user_scope_fixture()
      contract = %Contract{id: 1, user_id: scope.user.id}

      changeset = Contract.archive_changeset(contract, scope)

      assert Ecto.Changeset.get_change(changeset, :archived) == true
    end

    test "sets archived_by_id to user_scope.user.id" do
      scope = user_scope_fixture()
      contract = %Contract{id: 1, user_id: scope.user.id}

      changeset = Contract.archive_changeset(contract, scope)

      assert Ecto.Changeset.get_change(changeset, :archived_by_id) == scope.user.id
    end
  end
end
