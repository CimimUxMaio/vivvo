defmodule Vivvo.ContractsTest do
  use Vivvo.DataCase

  alias Vivvo.Contracts
  alias Vivvo.Contracts.Contract
  alias Vivvo.Repo

  import Vivvo.AccountsFixtures, only: [user_scope_fixture: 0, user_fixture: 1]
  import Vivvo.ContractsFixtures
  import Vivvo.PaymentsFixtures
  import Vivvo.PropertiesFixtures

  @invalid_attrs %{start_date: nil, end_date: nil, expiration_day: nil, notes: nil}

  describe "list_contracts/1" do
    test "returns all scoped contracts" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      contract = contract_fixture(scope)
      other_contract = contract_fixture(other_scope)
      assert Enum.map(Contracts.list_contracts(scope), & &1.id) == [contract.id]
      assert Enum.map(Contracts.list_contracts(other_scope), & &1.id) == [other_contract.id]
    end

    test "excludes archived contracts" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)
      {:ok, _archived} = Contracts.delete_contract(scope, contract)

      assert Contracts.list_contracts(scope) == []
    end

    test "includes only non-archived contracts" do
      scope = user_scope_fixture()
      active_contract = contract_fixture(scope)
      archived_contract = contract_fixture(scope)
      {:ok, _archived} = Contracts.delete_contract(scope, archived_contract)

      assert Enum.map(Contracts.list_contracts(scope), & &1.id) == [active_contract.id]
    end

    test "returns empty list when all contracts archived" do
      scope = user_scope_fixture()
      contract1 = contract_fixture(scope)
      contract2 = contract_fixture(scope)

      {:ok, _archived1} = Contracts.delete_contract(scope, contract1)
      {:ok, _archived2} = Contracts.delete_contract(scope, contract2)

      assert Contracts.list_contracts(scope) == []
    end
  end

  describe "get_contract!/2" do
    test "returns the contract with given id" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)
      other_scope = user_scope_fixture()
      result = Contracts.get_contract!(scope, contract.id)
      assert result.id == contract.id

      assert_raise Ecto.NoResultsError, fn ->
        Contracts.get_contract!(other_scope, contract.id)
      end
    end

    test "excludes archived contracts" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)
      {:ok, _archived} = Contracts.delete_contract(scope, contract)

      assert_raise Ecto.NoResultsError, fn ->
        Contracts.get_contract!(scope, contract.id)
      end
    end

    test "returns contract when not archived" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)

      result = Contracts.get_contract!(scope, contract.id)
      assert result.id == contract.id
    end

    test "preloads rent_periods association" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)

      result = Contracts.get_contract!(scope, contract.id)
      assert result.rent_periods != nil
      assert result.rent_periods != []
    end
  end

  describe "current_contract_for_property/2" do
    test "returns active contract for property" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)

      contract =
        contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      result = Contracts.current_contract_for_property(scope, property.id)

      assert result.id == contract.id
      assert result.property_id == property.id
    end

    test "returns nil when no active contract" do
      scope = user_scope_fixture()
      property = property_fixture(scope)

      assert Contracts.current_contract_for_property(scope, property.id) == nil
    end

    test "returns nil when only archived contracts exist" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)

      contract =
        contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      {:ok, _archived} = Contracts.delete_contract(scope, contract)

      assert Contracts.current_contract_for_property(scope, property.id) == nil
    end

    test "preloads tenant association" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)

      contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      result = Contracts.current_contract_for_property(scope, property.id)

      assert result.tenant != nil
      assert result.tenant.id == tenant.id
    end

    test "scoped to current user" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)

      contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      assert Contracts.current_contract_for_property(other_scope, property.id) == nil
    end

    test "preloads rent_periods association" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)

      contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      result = Contracts.current_contract_for_property(scope, property.id)
      assert result.rent_periods != nil
      assert result.rent_periods != []
    end

    test "returns contract active on specific date" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)
      today = Date.utc_today()

      # Create contract starting today
      _contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id,
          start_date: today,
          end_date: Date.add(today, 60)
        })

      # Should find contract when querying today
      assert Contracts.current_contract_for_property(scope, property.id, today) != nil

      # Should not find contract when querying before start_date
      assert Contracts.current_contract_for_property(scope, property.id, Date.add(today, -1)) ==
               nil

      # Should not find contract when querying after end_date
      assert Contracts.current_contract_for_property(scope, property.id, Date.add(today, 61)) ==
               nil
    end
  end

  describe "create_contract/2" do
    test "with valid data creates a contract" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)

      today = Date.utc_today()

      valid_attrs = %{
        start_date: today,
        end_date: Date.add(today, 30),
        expiration_day: 5,
        notes: "some notes",
        rent: "120.5",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:ok, %Contract{} = contract} = Contracts.create_contract(scope, valid_attrs)
      assert contract.start_date == today
      assert contract.end_date == Date.add(today, 30)
      assert contract.expiration_day == 5
      assert contract.notes == "some notes"
      assert contract.user_id == scope.user.id
      assert contract.property_id == property.id
      assert contract.tenant_id == tenant.id

      # Verify rent period was created
      assert length(contract.rent_periods) == 1
      [rent_period] = contract.rent_periods
      assert Decimal.equal?(rent_period.value, Decimal.new("120.5"))
      assert rent_period.start_date == today
      assert rent_period.end_date == Date.add(today, 30)
      assert rent_period.index_type == nil
      assert rent_period.index_value == nil
    end

    test "with rent_period_duration calculates correct end_date" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)
      today = Date.utc_today()

      valid_attrs = %{
        start_date: today,
        end_date: Date.add(today, 365),
        expiration_day: 5,
        rent: "1200.00",
        rent_period_duration: 3,
        index_type: :cpi,
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:ok, %Contract{} = contract} = Contracts.create_contract(scope, valid_attrs)
      assert contract.rent_period_duration == 3

      # With 3-month duration starting today:
      # beginning_of_month(today) = first day of current month
      # shift by (3-1) = 2 months = first day of month + 2 months
      # end_of_month(...) = last day of that month
      [rent_period] = contract.rent_periods
      assert rent_period.start_date == today

      expected_end =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: 2)
        |> Date.end_of_month()

      assert rent_period.end_date == expected_end
    end

    test "without rent_period_duration creates single period spanning entire contract" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)
      today = Date.utc_today()

      valid_attrs = %{
        start_date: today,
        end_date: Date.add(today, 365),
        expiration_day: 5,
        rent: "1000.00",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:ok, %Contract{} = contract} = Contracts.create_contract(scope, valid_attrs)
      assert contract.rent_period_duration == nil

      [rent_period] = contract.rent_periods
      assert rent_period.start_date == today
      assert rent_period.end_date == Date.add(today, 365)
    end

    test "with index_type and index_value" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)
      today = Date.utc_today()

      valid_attrs = %{
        start_date: today,
        end_date: Date.add(today, 365),
        expiration_day: 5,
        rent: "1000.00",
        rent_period_duration: 12,
        index_type: :cpi,
        index_value: "3.0",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:ok, %Contract{} = contract} = Contracts.create_contract(scope, valid_attrs)
      assert contract.index_type == :cpi
      [rent_period] = contract.rent_periods
      assert rent_period.index_type == :cpi
      # Initial rent period still has nil index value
      assert rent_period.index_value == nil
    end

    test "with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Contracts.create_contract(scope, @invalid_attrs)
    end

    test "returns overlapping_contract error when new contract overlaps at start" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)
      today = Date.utc_today()

      # Create existing contract: today to 6 months later
      existing_attrs = %{
        start_date: today,
        end_date: Date.add(today, 180),
        expiration_day: 5,
        rent: "1000.00",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:ok, %Contract{} = existing_contract} =
               Contracts.create_contract(scope, existing_attrs)

      # Try to create overlapping contract: 2 months later to 12 months later (overlaps at start)
      overlapping_attrs = %{
        start_date: Date.add(today, 60),
        end_date: Date.add(today, 365),
        expiration_day: 5,
        rent: "1200.00",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:error, :overlapping_contract, returned_contract} =
               Contracts.create_contract(scope, overlapping_attrs)

      assert returned_contract.id == existing_contract.id
    end

    test "returns overlapping_contract error when new contract overlaps at end" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)
      today = Date.utc_today()

      # Create existing contract: 6 months from now to 12 months from now
      existing_attrs = %{
        start_date: Date.add(today, 180),
        end_date: Date.add(today, 365),
        expiration_day: 5,
        rent: "1000.00",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:ok, %Contract{} = existing_contract} =
               Contracts.create_contract(scope, existing_attrs)

      # Try to create overlapping contract: today to 8 months later (overlaps at end)
      overlapping_attrs = %{
        start_date: today,
        end_date: Date.add(today, 240),
        expiration_day: 5,
        rent: "1200.00",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:error, :overlapping_contract, returned_contract} =
               Contracts.create_contract(scope, overlapping_attrs)

      assert returned_contract.id == existing_contract.id
    end

    test "returns overlapping_contract error when new contract completely contains existing" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)
      today = Date.utc_today()

      # Create existing contract: 3 months from now to 9 months from now
      existing_attrs = %{
        start_date: Date.add(today, 90),
        end_date: Date.add(today, 270),
        expiration_day: 5,
        rent: "1000.00",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:ok, %Contract{} = existing_contract} =
               Contracts.create_contract(scope, existing_attrs)

      # Try to create overlapping contract: today to 12 months later (completely contains existing)
      overlapping_attrs = %{
        start_date: today,
        end_date: Date.add(today, 365),
        expiration_day: 5,
        rent: "1200.00",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:error, :overlapping_contract, returned_contract} =
               Contracts.create_contract(scope, overlapping_attrs)

      assert returned_contract.id == existing_contract.id
    end

    test "allows creating contract when no overlap exists" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)
      today = Date.utc_today()

      # Create existing contract: today to 6 months later
      existing_attrs = %{
        start_date: today,
        end_date: Date.add(today, 180),
        expiration_day: 5,
        rent: "1000.00",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:ok, %Contract{}} = Contracts.create_contract(scope, existing_attrs)

      # Create non-overlapping contract: 6 months + 1 day later to 12 months later (starts after existing ends)
      non_overlapping_start = Date.add(today, 181)

      non_overlapping_attrs = %{
        start_date: non_overlapping_start,
        end_date: Date.add(today, 365),
        expiration_day: 5,
        rent: "1200.00",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:ok, %Contract{} = new_contract} =
               Contracts.create_contract(scope, non_overlapping_attrs)

      assert new_contract.start_date == non_overlapping_start
      assert new_contract.end_date == Date.add(today, 365)
    end

    test "returns past_start_date error when start_date is in the past" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)
      today = Date.utc_today()
      past_date = Date.add(today, -30)

      attrs = %{
        start_date: past_date,
        end_date: Date.add(today, 30),
        expiration_day: 5,
        rent: "1000.00",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:error, {:past_start_date, returned_date}} = Contracts.create_contract(scope, attrs)
      assert returned_date == past_date
    end

    test "raises ArgumentError when only past_start_date? option is provided" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)
      today = Date.utc_today()

      attrs = %{
        start_date: Date.add(today, -30),
        end_date: Date.add(today, 30),
        expiration_day: 5,
        rent: "1000.00",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert_raise ArgumentError,
                   "index_value option must be provided when past_start_date? is true",
                   fn ->
                     Contracts.create_contract(scope, attrs, past_start_date?: true)
                   end
    end

    test "creates contract with multiple rent periods when using past date options" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)
      today = Date.utc_today()

      # Create a contract starting 6 months ago with 3-month rent periods
      # This should generate at least 2-3 rent periods to cover up to today
      attrs = %{
        start_date: Date.add(today, -180),
        end_date: Date.add(today, 180),
        expiration_day: 5,
        rent: "1000.00",
        rent_period_duration: 3,
        index_type: :fixed_percentage,
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:ok, %Contract{} = contract} =
               Contracts.create_contract(scope, attrs,
                 past_start_date?: true,
                 index_value: Decimal.new("0.05")
               )

      # Should have multiple rent periods (at least 2, probably 3)
      assert length(contract.rent_periods) >= 2

      # First period should have the initial rent
      first_period = Enum.min_by(contract.rent_periods, & &1.start_date, Date)
      assert Decimal.equal?(first_period.value, Decimal.new("1000.00"))
      assert first_period.start_date == Date.add(today, -180)

      # Verify periods have increasing rent values (applying 5% index)
      sorted_periods = Enum.sort_by(contract.rent_periods, & &1.start_date, Date)

      sorted_periods
      |> Enum.with_index()
      |> Enum.reduce(nil, fn {period, index}, prev_rent ->
        assert period.index_type == :fixed_percentage
        assert period.index_value == ((index > 0 && Decimal.new("0.05")) || nil)

        if index > 0 do
          expected_rent = Decimal.mult(prev_rent, Decimal.new("1.05"))
          assert Decimal.compare(period.value, expected_rent) == :eq
        end

        period.value
      end)

      # The last period should cover today's date or later
      last_period = List.last(sorted_periods)
      assert Date.compare(last_period.end_date, today) != :lt
    end

    test "archived contracts do not block new contracts" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)
      today = Date.utc_today()

      # Create existing contract: today to 6 months later
      existing_attrs = %{
        start_date: today,
        end_date: Date.add(today, 180),
        expiration_day: 5,
        rent: "1000.00",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:ok, existing_contract} = Contracts.create_contract(scope, existing_attrs)

      # Archive the contract
      assert {:ok, _} = Contracts.delete_contract(scope, existing_contract)

      # Create overlapping contract: 2 months later to 9 months later (would overlap if not archived)
      new_start = Date.add(today, 60)
      new_end = Date.add(today, 270)

      overlapping_attrs = %{
        start_date: new_start,
        end_date: new_end,
        expiration_day: 5,
        rent: "1200.00",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:ok, %Contract{} = new_contract} =
               Contracts.create_contract(scope, overlapping_attrs)

      assert new_contract.start_date == new_start
      assert new_contract.end_date == new_end
    end

    test "contracts for different properties do not block each other" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property1 = property_fixture(scope)
      property2 = property_fixture(scope)
      today = Date.utc_today()

      # Create contract for property1: today to 6 months later
      existing_attrs = %{
        start_date: today,
        end_date: Date.add(today, 180),
        expiration_day: 5,
        rent: "1000.00",
        property_id: property1.id,
        tenant_id: tenant.id
      }

      assert {:ok, %Contract{}} = Contracts.create_contract(scope, existing_attrs)

      # Create overlapping dates but for different property
      new_contract_attrs = %{
        start_date: Date.add(today, 60),
        end_date: Date.add(today, 270),
        expiration_day: 5,
        rent: "1200.00",
        property_id: property2.id,
        tenant_id: tenant.id
      }

      assert {:ok, %Contract{} = new_contract} =
               Contracts.create_contract(scope, new_contract_attrs)

      assert new_contract.property_id == property2.id
    end
  end

  describe "delete_contract/2" do
    test "archives instead of deleting from database" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)

      assert {:ok, %Contract{}} =
               Contracts.delete_contract(scope, contract)

      # Record should still exist in DB with archived=true
      archived_contract =
        Repo.get_by(Contract, id: contract.id, user_id: scope.user.id, archived: true)

      assert archived_contract != nil
      assert archived_contract.archived == true
    end

    test "record still exists in DB with archived=true" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)

      {:ok, _} = Contracts.delete_contract(scope, contract)

      # Query directly from database
      archived = Repo.get(Contract, contract.id)
      assert archived != nil
      assert archived.archived == true
    end

    test "sets archived_by_id" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)

      {:ok, _} = Contracts.delete_contract(scope, contract)

      archived = Repo.get(Contract, contract.id)
      assert archived.archived_by_id == scope.user.id
    end

    test "with invalid scope returns unauthorized error" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      contract = contract_fixture(scope)
      assert {:error, :unauthorized} = Contracts.delete_contract(other_scope, contract)
    end

    test "rent periods are preserved when contract is archived" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)

      # Get rent periods before archiving
      original_periods = contract.rent_periods
      original_period_count = length(original_periods)

      {:ok, _} = Contracts.delete_contract(scope, contract)

      # Verify rent periods still exist
      archived = Repo.get(Contract, contract.id)
      archived_with_periods = Repo.preload(archived, :rent_periods)

      assert length(archived_with_periods.rent_periods) == original_period_count
    end
  end

  describe "change_contract/2" do
    test "returns a contract changeset" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)
      assert %Ecto.Changeset{} = Contracts.change_contract(scope, contract)
    end
  end

  describe "contract_status/1" do
    test "returns :upcoming when start_date in future" do
      contract = %Contract{
        start_date: Date.add(Date.utc_today(), 10),
        end_date: Date.add(Date.utc_today(), 20)
      }

      assert Contracts.contract_status(contract) == :upcoming
    end

    test "returns :active when today between start and end dates" do
      contract = %Contract{
        start_date: Date.add(Date.utc_today(), -10),
        end_date: Date.add(Date.utc_today(), 10)
      }

      assert Contracts.contract_status(contract) == :active
    end

    test "returns :expired when end_date in past" do
      contract = %Contract{
        start_date: Date.add(Date.utc_today(), -20),
        end_date: Date.add(Date.utc_today(), -10)
      }

      assert Contracts.contract_status(contract) == :expired
    end

    test "boundary condition - today equals start_date" do
      today = Date.utc_today()

      contract = %Contract{
        start_date: today,
        end_date: Date.add(today, 10)
      }

      assert Contracts.contract_status(contract) == :active
    end

    test "boundary condition - today equals end_date" do
      today = Date.utc_today()

      contract = %Contract{
        start_date: Date.add(today, -10),
        end_date: today
      }

      assert Contracts.contract_status(contract) == :active
    end
  end

  describe "payment_overdue?/2" do
    test "returns true when current day > expiration_day" do
      # Use a fixed date where day > expiration_day
      today = ~D[2026-02-15]
      expiration_day = 10

      contract = %Contract{
        expiration_day: expiration_day
      }

      assert Contracts.payment_overdue?(contract, today) == true
    end

    test "returns false when current day < expiration_day" do
      # Use a fixed date where we control the relationship
      # Feb 15 has day=15, so expiration_day=20 will always be greater
      today = ~D[2026-02-15]
      expiration_day = 20

      contract = %Contract{
        expiration_day: expiration_day
      }

      assert Contracts.payment_overdue?(contract, today) == false
    end

    test "returns false when current day = expiration_day" do
      # Use a fixed date where day equals expiration_day
      today = ~D[2026-02-15]
      expiration_day = 15

      contract = %Contract{
        expiration_day: expiration_day
      }

      assert Contracts.payment_overdue?(contract, today) == false
    end
  end

  describe "get_past_payment_numbers/2" do
    test "returns empty range when contract hasn't started yet" do
      scope = user_scope_fixture()
      future_start = Date.add(Date.utc_today(), 30)

      contract =
        contract_fixture(scope, %{
          start_date: future_start,
          end_date: Date.add(future_start, 365),
          expiration_day: 10
        })

      today = Date.utc_today()
      result = Contracts.get_past_payment_numbers(contract, today)

      assert result == []
    end

    test "includes current payment number when its due date has passed" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      # Contract started 2 months ago, with expiration day 1 (already passed)
      start_date = Date.add(today, -60)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: start_date,
            end_date: Date.add(start_date, 365),
            expiration_day: 1,
            index_type: :fixed_percentage,
            rent_period_duration: 12
          },
          past_start_date?: true,
          index_value: Decimal.new("0.0")
        )

      result = Contracts.get_past_payment_numbers(contract, today)

      # Due date is day 1, today is after that, so both months should be past
      assert Enum.count(result) >= 2
      assert List.first(result) == 1
    end

    test "excludes current payment number when its due date hasn't passed" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      # Contract starting today with expiration_day in the future
      start_date = today
      # Use tomorrow's day number (or 28 if today is end of month)
      expiration_day = min(today.day + 1, 28)

      contract =
        contract_fixture(scope, %{
          start_date: start_date,
          end_date: Date.add(start_date, 365),
          expiration_day: expiration_day
        })

      result = Contracts.get_past_payment_numbers(contract, today)

      # Current month hasn't passed yet since expiration_day > today.day
      # For a contract starting today, current payment number is 1
      # but no periods have passed yet, so result should be empty
      current = Contracts.get_current_payment_number(contract)
      assert current == 1
      assert result == []
    end
  end

  describe "current_rent_period/2" do
    test "returns correct period when date falls within range" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      contract =
        contract_fixture(scope, %{
          start_date: today,
          end_date: Date.add(today, 365),
          rent: "1000.00"
        })

      # The date today should be covered by the rent period
      period = Contracts.current_rent_period(contract, today)
      assert period != nil
      assert Decimal.equal?(period.value, Decimal.new("1000.00"))
      assert Date.compare(period.start_date, today) != :gt
      assert Date.compare(period.end_date, today) != :lt
    end

    test "returns earliest period for future contracts" do
      scope = user_scope_fixture()
      future_start = Date.add(Date.utc_today(), 30)

      contract =
        contract_fixture(scope, %{
          start_date: future_start,
          end_date: Date.add(future_start, 365),
          rent: "1000.00"
        })

      # For a future contract, should return the earliest period
      today = Date.utc_today()
      period = Contracts.current_rent_period(contract, today)
      assert period != nil
      assert Decimal.equal?(period.value, Decimal.new("1000.00"))
      # Should be the earliest (and only) period
      assert period.start_date == future_start
    end

    test "raises when contract has no rent periods" do
      _scope = user_scope_fixture()

      # Create a contract-like struct without rent periods
      contract = %Contract{
        id: 999_999,
        start_date: Date.utc_today(),
        end_date: Date.add(Date.utc_today(), 365),
        rent_periods: []
      }

      today = Date.utc_today()

      assert_raise RuntimeError, ~r/has no current rent period/, fn ->
        Contracts.current_rent_period(contract, today)
      end
    end

    test "raises when active contract has no matching period" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create a contract that started in the past
      contract =
        contract_fixture(
          scope,
          %{
            start_date: Date.add(today, -90),
            end_date: Date.add(today, 365),
            rent: "1000.00",
            index_type: :fixed_percentage,
            rent_period_duration: 12
          },
          past_start_date?: true,
          index_value: Decimal.new("0.0")
        )

      # Manually create a contract struct with rent periods that don't cover today
      contract_with_bad_periods = %{
        contract
        | rent_periods: [
            %Vivvo.Contracts.RentPeriod{
              start_date: Date.add(today, -90),
              end_date: Date.add(today, -60),
              value: Decimal.new("1000.00")
            }
          ]
      }

      # This should raise because the contract has started but no period covers today
      assert_raise RuntimeError, ~r/has no current rent period/, fn ->
        Contracts.current_rent_period(contract_with_bad_periods, today)
      end
    end

    test "handles edge case: date exactly on start_date boundary" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      start_date = today

      contract =
        contract_fixture(scope, %{
          start_date: start_date,
          end_date: Date.add(today, 365),
          rent: "1000.00"
        })

      # Date exactly at start should be included
      period = Contracts.current_rent_period(contract, start_date)
      assert period != nil
      assert Decimal.equal?(period.value, Decimal.new("1000.00"))
    end

    test "handles edge case: date exactly on end_date boundary" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      end_date = Date.add(today, 365)

      contract =
        contract_fixture(scope, %{
          start_date: today,
          end_date: end_date,
          rent: "1000.00"
        })

      # Get the rent period's end date
      [rent_period] = contract.rent_periods
      period_end = rent_period.end_date

      # Date exactly at end should be included
      period = Contracts.current_rent_period(contract, period_end)
      assert period != nil
      assert Decimal.equal?(period.value, Decimal.new("1000.00"))
    end

    test "handles multiple rent periods correctly" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create contract starting today
      contract =
        contract_fixture(scope, %{
          start_date: today,
          end_date: Date.add(today, 365),
          rent: "1000.00"
        })

      # Get the period that covers today
      period = Contracts.current_rent_period(contract, today)
      assert period != nil
    end

    test "returns latest period for expired contracts" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      contract =
        expired_contract_fixture(scope, %{rent: "900.00"})

      period = Contracts.current_rent_period(contract, today)
      assert period != nil
      assert Decimal.equal?(period.value, Decimal.new("900.00"))
      # The returned period should be the latest one (closest to end_date)
      assert Date.compare(period.end_date, today) == :lt
    end
  end

  describe "current_rent_value/2" do
    test "returns rent value for current date" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      contract =
        contract_fixture(scope, %{
          start_date: today,
          end_date: Date.add(today, 365),
          rent: "1500.00"
        })

      rent_value = Contracts.current_rent_value(contract, today)
      assert Decimal.equal?(rent_value, Decimal.new("1500.00"))
    end

    test "returns rent value for future contracts" do
      scope = user_scope_fixture()
      future_start = Date.add(Date.utc_today(), 30)

      contract =
        contract_fixture(scope, %{
          start_date: future_start,
          end_date: Date.add(future_start, 365),
          rent: "2000.00"
        })

      today = Date.utc_today()
      rent_value = Contracts.current_rent_value(contract, today)
      assert Decimal.equal?(rent_value, Decimal.new("2000.00"))
    end

    test "defaults to today when no date provided" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      contract =
        contract_fixture(scope, %{
          start_date: today,
          end_date: Date.add(today, 365),
          rent: "1200.00"
        })

      rent_value = Contracts.current_rent_value(contract)
      assert Decimal.equal?(rent_value, Decimal.new("1200.00"))
    end

    test "returns latest period rent value for expired contracts" do
      scope = user_scope_fixture()

      contract =
        expired_contract_fixture(scope, %{rent: "850.00"})

      rent_value = Contracts.current_rent_value(contract)
      assert Decimal.equal?(rent_value, Decimal.new("850.00"))
    end
  end

  describe "property_performance_metrics with cumulative collection" do
    setup do
      owner_scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      tenant_scope = %Vivvo.Accounts.Scope{user: tenant}
      %{scope: owner_scope, tenant_scope: tenant_scope}
    end

    test "calculates cumulative collection for past due dates", %{
      scope: scope,
      tenant_scope: tenant_scope
    } do
      today = Date.utc_today()
      # Create contract with multiple months (started 3 months ago)
      contract =
        contract_fixture(
          scope,
          %{
            rent: "1000.00",
            start_date: Date.add(today, -90),
            end_date: Date.add(today, 365),
            expiration_day: 1,
            tenant_id: tenant_scope.user.id,
            index_type: :fixed_percentage,
            rent_period_duration: 12
          },
          past_start_date?: true,
          index_value: Decimal.new("0.0")
        )

      property_id = contract.property_id

      # Get current payment number to determine expected periods
      current = Contracts.get_current_payment_number(contract)

      # Determine how many periods are in the past
      expected_periods =
        if Date.compare(
             Contracts.calculate_due_date(contract, current),
             today
           ) == :lt do
          current
        else
          current - 1
        end

      # Pay first month fully - create as pending (tenant) then accept (owner)
      payment =
        payment_fixture(tenant_scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "1000.00",
          status: :pending
        })

      {:ok, _payment} = Vivvo.Payments.accept_payment(scope, payment)

      # Get metrics - need to use same property scope
      metrics =
        scope
        |> Contracts.property_performance_metrics()
        |> Enum.find(&(&1.property.id == property_id))

      # Verify expected is rent × periods
      assert Decimal.eq?(metrics.total_expected, Decimal.new(1000 * expected_periods))

      # Verify income is $1000 (only first month paid)
      assert Decimal.eq?(metrics.total_income, Decimal.new("1000.00"))

      # Verify collection rate
      expected_rate = if expected_periods > 0, do: 100.0 / expected_periods, else: 0.0
      assert_in_delta metrics.collection_rate, expected_rate, 0.1
    end

    test "returns zero for new contract with no past due dates", %{scope: scope} do
      today = Date.utc_today()
      future_start = Date.add(today, 60)

      # Create contract that starts far in the future (no past due dates)
      contract =
        contract_fixture(scope, %{
          rent: "1000.00",
          start_date: future_start,
          end_date: Date.add(future_start, 365),
          expiration_day: 10
        })

      property_id = contract.property_id

      metrics =
        scope
        |> Contracts.property_performance_metrics()
        |> Enum.find(&(&1.property.id == property_id))

      assert metrics != nil
      assert metrics.property.id == property_id
      assert Decimal.eq?(metrics.total_expected, Decimal.new("0"))
      assert Decimal.eq?(metrics.total_income, Decimal.new("0"))
      assert metrics.collection_rate == 0.0
    end

    test "shows 100% collection when all past periods paid", %{
      scope: scope,
      tenant_scope: tenant_scope
    } do
      today = Date.utc_today()

      # Create contract that started 2 months ago
      contract =
        contract_fixture(
          scope,
          %{
            rent: "500.00",
            start_date: Date.add(today, -60),
            end_date: Date.add(today, 365),
            expiration_day: 1,
            tenant_id: tenant_scope.user.id,
            index_type: :fixed_percentage,
            rent_period_duration: 12
          },
          past_start_date?: true,
          index_value: Decimal.new("0.0")
        )

      property_id = contract.property_id

      # Determine how many periods are in the past
      current = Contracts.get_current_payment_number(contract)

      periods =
        if Date.compare(
             Contracts.calculate_due_date(contract, current),
             today
           ) == :lt do
          current
        else
          current - 1
        end

      # Pay all past periods - create as pending (tenant) then accept (owner)
      for num <- 1..periods do
        payment =
          payment_fixture(tenant_scope, %{
            contract_id: contract.id,
            payment_number: num,
            amount: "500.00",
            status: :pending
          })

        {:ok, _} = Vivvo.Payments.accept_payment(scope, payment)
      end

      metrics =
        scope
        |> Contracts.property_performance_metrics()
        |> Enum.find(&(&1.property.id == property_id))

      assert Decimal.eq?(metrics.total_expected, Decimal.new(500 * periods))
      assert Decimal.eq?(metrics.total_income, Decimal.new(500 * periods))
      assert metrics.collection_rate == 100.0
    end

    test "handles vacant property", %{scope: scope} do
      property = property_fixture(scope)

      metrics =
        scope
        |> Contracts.property_performance_metrics()
        |> Enum.find(&(&1.property.id == property.id))

      assert metrics != nil
      assert metrics.property.id == property.id
      assert metrics.state == :vacant
      assert Decimal.eq?(metrics.total_expected, Decimal.new("0"))
      assert Decimal.eq?(metrics.total_income, Decimal.new("0"))
      assert metrics.collection_rate == 0.0
      assert metrics.avg_delay_days == 0
    end
  end

  describe "calculate_avg_delay_days/3" do
    setup do
      owner_scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      tenant_scope = %Vivvo.Accounts.Scope{user: tenant}
      %{scope: owner_scope, tenant_scope: tenant_scope}
    end

    # Helper to create a contract with exactly one past due payment period
    defp create_single_period_contract(scope, tenant_scope, today) do
      # Start date in the current month, with expiration_day = 1 (already passed)
      start_date = Date.beginning_of_month(today)

      contract_fixture(
        scope,
        %{
          rent: "1000.00",
          start_date: start_date,
          end_date: Date.add(start_date, 365),
          expiration_day: 1,
          tenant_id: tenant_scope.user.id,
          index_type: :fixed_percentage,
          rent_period_duration: 12
        },
        past_start_date?: true,
        index_value: Decimal.new("0.0")
      )
    end

    test "multiple partial payments - uses completion payment delay only", %{
      scope: scope,
      tenant_scope: tenant_scope
    } do
      today = Date.utc_today()
      contract = create_single_period_contract(scope, tenant_scope, today)

      # Get due date for month 1
      due_date = Contracts.calculate_due_date(contract, 1)

      # Verify we have exactly 1 past period
      past_periods = Contracts.get_past_payment_numbers(contract, today)
      assert Enum.count(past_periods) == 1

      # Payment 1: $600 on day -5 (5 days early)
      early_payment_date = Date.add(due_date, -5)

      payment1 =
        payment_fixture(tenant_scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "600.00",
          status: :pending
        })

      # Update inserted_at to simulate early payment
      Ecto.Changeset.change(payment1, %{})
      |> Ecto.Changeset.force_change(
        :inserted_at,
        DateTime.new!(early_payment_date, ~T[12:00:00], "Etc/UTC")
      )
      |> Repo.update!()

      {:ok, _} = Vivvo.Payments.accept_payment(scope, payment1)

      # Payment 2: $400 on day +3 (3 days late) - this completes the rent
      late_payment_date = Date.add(due_date, 3)

      payment2 =
        payment_fixture(tenant_scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "400.00",
          status: :pending
        })

      Ecto.Changeset.change(payment2, %{})
      |> Ecto.Changeset.force_change(
        :inserted_at,
        DateTime.new!(late_payment_date, ~T[12:00:00], "Etc/UTC")
      )
      |> Repo.update!()

      {:ok, _} = Vivvo.Payments.accept_payment(scope, payment2)

      # Get payments grouped by month
      payments_by_month = Vivvo.Payments.get_contract_payments_by_month(scope, contract.id)

      # Calculate avg delay - should be 3 days (completion payment delay only, not average of -5 and 3)
      avg_delay = Contracts.calculate_avg_delay_days(contract, payments_by_month, today)

      # Expected: 3 days (the delay of the completion payment)
      assert avg_delay == 3.0
    end

    test "single full payment (regression test)", %{scope: scope, tenant_scope: tenant_scope} do
      today = Date.utc_today()
      contract = create_single_period_contract(scope, tenant_scope, today)
      due_date = Contracts.calculate_due_date(contract, 1)

      # Verify we have exactly 1 past period
      past_periods = Contracts.get_past_payment_numbers(contract, today)
      assert Enum.count(past_periods) == 1

      # Single payment of $1000 on day +5 (5 days late)
      payment_date = Date.add(due_date, 5)

      payment =
        payment_fixture(tenant_scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "1000.00",
          status: :pending
        })

      Ecto.Changeset.change(payment, %{})
      |> Ecto.Changeset.force_change(
        :inserted_at,
        DateTime.new!(payment_date, ~T[12:00:00], "Etc/UTC")
      )
      |> Repo.update!()

      {:ok, _} = Vivvo.Payments.accept_payment(scope, payment)

      payments_by_month = Vivvo.Payments.get_contract_payments_by_month(scope, contract.id)
      avg_delay = Contracts.calculate_avg_delay_days(contract, payments_by_month, today)

      assert avg_delay == 5.0
    end

    test "mix of fully paid and partially paid months", %{
      scope: scope,
      tenant_scope: tenant_scope
    } do
      today = Date.utc_today()
      # Contract started ~2 months ago to ensure exactly 3 payment periods
      # Using 55 days ensures we span 3 months but don't create a 4th period
      start_date = Date.add(today, -55)

      contract =
        contract_fixture(
          scope,
          %{
            rent: "1000.00",
            start_date: start_date,
            end_date: Date.add(start_date, 365),
            expiration_day: 1,
            tenant_id: tenant_scope.user.id,
            index_type: :fixed_percentage,
            rent_period_duration: 12
          },
          past_start_date?: true,
          index_value: Decimal.new("0.0")
        )

      # Verify we have exactly 3 past payment periods
      past_periods = Contracts.get_past_payment_numbers(contract, today)
      assert Enum.count(past_periods) == 3

      # Month 1: Single payment of $1000 on day +2
      due_date_1 = Contracts.calculate_due_date(contract, 1)

      payment_1 =
        payment_fixture(tenant_scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "1000.00",
          status: :pending
        })

      Ecto.Changeset.change(payment_1, %{})
      |> Ecto.Changeset.force_change(
        :inserted_at,
        DateTime.new!(Date.add(due_date_1, 2), ~T[12:00:00], "Etc/UTC")
      )
      |> Repo.update!()

      {:ok, _} = Vivvo.Payments.accept_payment(scope, payment_1)

      # Month 2: Two payments ($500 day -3, $500 day +5) - completion on day +5
      due_date_2 = Contracts.calculate_due_date(contract, 2)

      payment_2a =
        payment_fixture(tenant_scope, %{
          contract_id: contract.id,
          payment_number: 2,
          amount: "500.00",
          status: :pending
        })

      Ecto.Changeset.change(payment_2a, %{})
      |> Ecto.Changeset.force_change(
        :inserted_at,
        DateTime.new!(Date.add(due_date_2, -3), ~T[12:00:00], "Etc/UTC")
      )
      |> Repo.update!()

      {:ok, _} = Vivvo.Payments.accept_payment(scope, payment_2a)

      payment_2b =
        payment_fixture(tenant_scope, %{
          contract_id: contract.id,
          payment_number: 2,
          amount: "500.00",
          status: :pending
        })

      Ecto.Changeset.change(payment_2b, %{})
      |> Ecto.Changeset.force_change(
        :inserted_at,
        DateTime.new!(Date.add(due_date_2, 5), ~T[12:00:00], "Etc/UTC")
      )
      |> Repo.update!()

      {:ok, _} = Vivvo.Payments.accept_payment(scope, payment_2b)

      # Month 3: Partially paid ($600) - uses today for delay
      due_date_3 = Contracts.calculate_due_date(contract, 3)

      payment_3 =
        payment_fixture(tenant_scope, %{
          contract_id: contract.id,
          payment_number: 3,
          amount: "600.00",
          status: :pending
        })

      {:ok, _} = Vivvo.Payments.accept_payment(scope, payment_3)

      payments_by_month = Vivvo.Payments.get_contract_payments_by_month(scope, contract.id)

      # Calculate expected delay for month 3 (partially paid - uses today)
      delay_month_3 = max(0, Date.diff(today, due_date_3))

      # Expected average: (2 + 5 + delay_month_3) / 3
      expected_avg = Float.round((2 + 5 + delay_month_3) / 3, 1)

      avg_delay = Contracts.calculate_avg_delay_days(contract, payments_by_month, today)

      assert avg_delay == expected_avg
    end

    test "early completion payments show 0 delay", %{scope: scope, tenant_scope: tenant_scope} do
      today = Date.utc_today()
      contract = create_single_period_contract(scope, tenant_scope, today)
      due_date = Contracts.calculate_due_date(contract, 1)

      # Verify we have exactly 1 past period
      past_periods = Contracts.get_past_payment_numbers(contract, today)
      assert Enum.count(past_periods) == 1

      # Payment 10 days early
      early_date = Date.add(due_date, -10)

      payment =
        payment_fixture(tenant_scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "1000.00",
          status: :pending
        })

      Ecto.Changeset.change(payment, %{})
      |> Ecto.Changeset.force_change(
        :inserted_at,
        DateTime.new!(early_date, ~T[12:00:00], "Etc/UTC")
      )
      |> Repo.update!()

      {:ok, _} = Vivvo.Payments.accept_payment(scope, payment)

      payments_by_month = Vivvo.Payments.get_contract_payments_by_month(scope, contract.id)
      avg_delay = Contracts.calculate_avg_delay_days(contract, payments_by_month, today)

      # Early payment = 0 delay (not negative)
      assert avg_delay == 0.0
    end

    test "no payments at all uses today as completion date", %{
      scope: scope,
      tenant_scope: tenant_scope
    } do
      today = Date.utc_today()
      contract = create_single_period_contract(scope, tenant_scope, today)
      due_date = Contracts.calculate_due_date(contract, 1)

      # Verify we have exactly 1 past period
      past_periods = Contracts.get_past_payment_numbers(contract, today)
      assert Enum.count(past_periods) == 1

      expected_delay = max(0, Date.diff(today, due_date))

      payments_by_month = Vivvo.Payments.get_contract_payments_by_month(scope, contract.id)
      avg_delay = Contracts.calculate_avg_delay_days(contract, payments_by_month, today)

      # Should be delay from due date to today
      assert avg_delay == Float.round(expected_delay / 1.0, 1)
    end

    test "overpayment treated as normal completion", %{scope: scope, tenant_scope: tenant_scope} do
      today = Date.utc_today()
      contract = create_single_period_contract(scope, tenant_scope, today)
      due_date = Contracts.calculate_due_date(contract, 1)

      # Verify we have exactly 1 past period
      past_periods = Contracts.get_past_payment_numbers(contract, today)
      assert Enum.count(past_periods) == 1

      # Overpayment of $1500 on day +3
      payment_date = Date.add(due_date, 3)

      payment =
        payment_fixture(tenant_scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "1500.00",
          status: :pending
        })

      Ecto.Changeset.change(payment, %{})
      |> Ecto.Changeset.force_change(
        :inserted_at,
        DateTime.new!(payment_date, ~T[12:00:00], "Etc/UTC")
      )
      |> Repo.update!()

      {:ok, _} = Vivvo.Payments.accept_payment(scope, payment)

      payments_by_month = Vivvo.Payments.get_contract_payments_by_month(scope, contract.id)
      avg_delay = Contracts.calculate_avg_delay_days(contract, payments_by_month, today)

      assert avg_delay == 3.0
    end

    test "contract with no past due dates returns 0.0", %{scope: scope} do
      today = Date.utc_today()
      # Future contract
      future_start = Date.add(today, 30)

      contract =
        contract_fixture(scope, %{
          rent: "1000.00",
          start_date: future_start,
          end_date: Date.add(future_start, 365),
          expiration_day: 10
        })

      payments_by_month = Vivvo.Payments.get_contract_payments_by_month(scope, contract.id)
      avg_delay = Contracts.calculate_avg_delay_days(contract, payments_by_month, today)

      assert avg_delay == 0.0
    end
  end

  describe "create_rent_period/1" do
    test "creates rent period with valid attributes" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)

      attrs = %{
        contract_id: contract.id,
        start_date: ~D[2026-01-01],
        end_date: ~D[2026-06-30],
        value: Decimal.new("1200.00"),
        index_type: :fixed_percentage,
        index_value: Decimal.new("0.03")
      }

      assert {:ok, %Vivvo.Contracts.RentPeriod{} = rent_period} =
               Contracts.create_rent_period(attrs)

      assert rent_period.value == Decimal.new("1200.00")
      assert rent_period.index_type == :fixed_percentage
    end

    test "returns error with invalid attributes" do
      attrs = %{
        contract_id: nil,
        start_date: nil,
        end_date: nil,
        value: nil
      }

      assert {:error, %Ecto.Changeset{}} = Contracts.create_rent_period(attrs)
    end
  end

  describe "get_system_contract/1" do
    test "returns contract with rent periods when found" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)

      result = Contracts.get_system_contract(contract.id)

      assert result.id == contract.id
      assert result.archived == false
      assert is_list(result.rent_periods)
    end

    test "returns nil when contract does not exist" do
      assert Contracts.get_system_contract(99_999_999) == nil
    end

    test "returns nil when contract is archived" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)

      # Archive the contract
      Repo.update!(Contract.archive_changeset(contract, scope))

      assert Contracts.get_system_contract(contract.id) == nil
    end
  end

  describe "contracts_needing_update/1" do
    test "returns contracts with rent period ending in current month" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      end_of_this_month = Date.end_of_month(today)

      # Create contract with rent period ending in the current month
      # Use today's date as start to avoid past_start_date requirement
      contract =
        contract_fixture(
          scope,
          %{
            start_date: today,
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :cpi
          }
        )

      # Delete auto-generated period from fixture
      contract = Contracts.get_contract!(scope, contract.id)

      Enum.each(contract.rent_periods, fn rp ->
        Repo.delete!(rp)
      end)

      _period =
        rent_period_fixture(contract, %{
          start_date: Date.add(end_of_this_month, -30),
          end_date: end_of_this_month,
          value: Decimal.new("1000.00"),
          index_type: :cpi,
          index_value: Decimal.new("0.03")
        })

      results = Contracts.contracts_needing_update(today)
      assert length(results) == 1
      assert hd(results).id == contract.id
    end

    test "excludes contracts with rent period ending in different month" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      contract =
        contract_fixture(
          scope,
          %{
            start_date: today,
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :fixed_percentage
          }
        )

      # Period ending next month
      _period =
        rent_period_fixture(contract, %{
          start_date: today,
          end_date: Date.end_of_month(Date.add(today, 30)),
          value: Decimal.new("1000.00"),
          index_type: :fixed_percentage,
          index_value: Decimal.new("0.05")
        })

      results = Contracts.contracts_needing_update(today)
      assert results == []
    end

    test "excludes archived contracts" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      end_of_this_month = Date.end_of_month(today)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: today,
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :cpi
          }
        )

      _period =
        rent_period_fixture(contract, %{
          start_date: Date.add(end_of_this_month, -30),
          end_date: end_of_this_month,
          value: Decimal.new("1000.00"),
          index_type: :cpi,
          index_value: Decimal.new("0.03")
        })

      # Archive the contract
      Repo.update!(Contract.archive_changeset(contract, scope))

      results = Contracts.contracts_needing_update(today)
      assert results == []
    end

    test "excludes contracts without index_type or rent_period_duration" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      end_of_this_month = Date.end_of_month(today)

      # Create contract without index_type and without rent_period_duration
      # Both must be nil or both must be set (validation requirement)
      contract_no_index =
        contract_fixture(
          scope,
          %{
            start_date: today,
            end_date: Date.add(today, 400)
          }
        )

      _period =
        rent_period_fixture(contract_no_index, %{
          start_date: Date.add(end_of_this_month, -30),
          end_date: end_of_this_month,
          value: Decimal.new("1000.00")
        })

      results = Contracts.contracts_needing_update(today)
      assert results == []
    end

    test "excludes contracts that have already ended" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      end_of_this_month = Date.end_of_month(today)

      # Create a contract that has already ended (end_date in the past)
      # We need to use past_start_date here since we're setting dates in the past
      contract =
        contract_fixture(
          scope,
          %{
            start_date: Date.add(today, -400),
            end_date: Date.add(today, -10),
            rent_period_duration: 6,
            index_type: :cpi
          },
          past_start_date?: true,
          index_value: Decimal.new("0.03")
        )

      # Delete auto-generated periods and create our own
      contract = Contracts.get_contract!(scope, contract.id)

      Enum.each(contract.rent_periods, fn rp ->
        Repo.delete!(rp)
      end)

      _period =
        rent_period_fixture(contract, %{
          start_date: Date.add(end_of_this_month, -30),
          end_date: end_of_this_month,
          value: Decimal.new("1000.00"),
          index_type: :cpi,
          index_value: Decimal.new("0.03")
        })

      results = Contracts.contracts_needing_update(today)
      assert results == []
    end

    test "returns empty list when no contracts need updates" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create a future contract - won't need updates
      _contract =
        contract_fixture(
          scope,
          %{
            start_date: Date.add(today, 30),
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :cpi
          }
        )

      results = Contracts.contracts_needing_update(today)
      assert results == []
    end
  end
end
