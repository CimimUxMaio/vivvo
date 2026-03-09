defmodule Vivvo.Contracts.RentPeriodTest do
  use Vivvo.DataCase, async: true

  alias Vivvo.Contracts.RentPeriod
  import Vivvo.AccountsFixtures, only: [user_scope_fixture: 0]
  import Vivvo.PropertiesFixtures
  import Vivvo.ContractsFixtures

  describe "changeset/2" do
    test "validates required fields" do
      changeset = RentPeriod.changeset(%RentPeriod{}, %{})

      assert %{
               value: ["can't be blank"],
               start_date: ["can't be blank"],
               end_date: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates value must be greater than 0 - value 0" do
      attrs = %{
        value: "0",
        start_date: ~D[2026-01-01],
        end_date: ~D[2026-12-31],
        contract_id: 1
      }

      changeset = RentPeriod.changeset(%RentPeriod{}, attrs)
      assert %{value: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "validates value must be greater than 0 - negative value" do
      attrs = %{
        value: "-100.00",
        start_date: ~D[2026-01-01],
        end_date: ~D[2026-12-31],
        contract_id: 1
      }

      changeset = RentPeriod.changeset(%RentPeriod{}, attrs)
      assert %{value: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "validates end_date must be after start_date" do
      attrs = %{
        value: "1000.00",
        start_date: ~D[2026-06-01],
        end_date: ~D[2026-01-01],
        contract_id: 1
      }

      changeset = RentPeriod.changeset(%RentPeriod{}, attrs)
      assert %{end_date: ["must be after start date"]} = errors_on(changeset)
    end

    test "validates end_date equal to start_date is invalid" do
      attrs = %{
        value: "1000.00",
        start_date: ~D[2026-01-15],
        end_date: ~D[2026-01-15],
        contract_id: 1
      }

      changeset = RentPeriod.changeset(%RentPeriod{}, attrs)
      assert %{end_date: ["must be after start date"]} = errors_on(changeset)
    end

    test "allows nil for index_type and index_value" do
      attrs = %{
        value: "1000.00",
        start_date: ~D[2026-01-01],
        end_date: ~D[2026-12-31],
        contract_id: 1,
        index_type: nil,
        index_value: nil
      }

      changeset = RentPeriod.changeset(%RentPeriod{}, attrs)
      assert changeset.valid?
    end

    test "accepts valid index_type values" do
      for index_type <- ["cpi", "fixed_percentage", nil] do
        attrs = %{
          value: "1000.00",
          start_date: ~D[2026-01-01],
          end_date: ~D[2026-12-31],
          contract_id: 1,
          index_type: index_type
        }

        changeset = RentPeriod.changeset(%RentPeriod{}, attrs)
        assert changeset.valid?, "Expected valid changeset for index_type: #{inspect(index_type)}"
      end
    end

    test "rejects invalid index_type values" do
      attrs = %{
        value: "1000.00",
        start_date: ~D[2026-01-01],
        end_date: ~D[2026-12-31],
        contract_id: 1,
        index_type: "invalid_type"
      }

      changeset = RentPeriod.changeset(%RentPeriod{}, attrs)
      refute changeset.valid?
      assert %{index_type: ["is invalid"]} = errors_on(changeset)
    end

    test "valid changeset with all required fields" do
      attrs = %{
        value: "1000.00",
        start_date: ~D[2026-01-01],
        end_date: ~D[2026-12-31],
        contract_id: 1
      }

      changeset = RentPeriod.changeset(%RentPeriod{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with index fields populated" do
      attrs = %{
        value: "1050.00",
        start_date: ~D[2026-01-01],
        end_date: ~D[2026-12-31],
        contract_id: 1,
        index_type: "fixed_percentage",
        index_value: "5.0"
      }

      changeset = RentPeriod.changeset(%RentPeriod{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with cpi index type" do
      attrs = %{
        value: "1030.00",
        start_date: ~D[2026-01-01],
        end_date: ~D[2026-12-31],
        contract_id: 1,
        index_type: "cpi",
        index_value: "3.0"
      }

      changeset = RentPeriod.changeset(%RentPeriod{}, attrs)
      assert changeset.valid?
    end
  end

  describe "database constraints" do
    test "successfully creates rent period with valid data" do
      scope = user_scope_fixture()
      property = property_fixture(scope)

      tenant =
        Vivvo.AccountsFixtures.user_fixture(%{preferred_roles: [:tenant]})

      contract = contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      attrs = %{
        value: Decimal.new("1000.00"),
        start_date: ~D[2026-01-01],
        end_date: ~D[2026-12-31],
        contract_id: contract.id
      }

      changeset = RentPeriod.changeset(%RentPeriod{}, attrs)
      assert {:ok, rent_period} = Repo.insert(changeset)

      assert rent_period.value == Decimal.new("1000.00")
      assert rent_period.start_date == ~D[2026-01-01]
      assert rent_period.end_date == ~D[2026-12-31]
      assert rent_period.contract_id == contract.id
      assert rent_period.index_type == nil
      assert rent_period.index_value == nil
    end
  end
end
