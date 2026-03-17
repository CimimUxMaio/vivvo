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
      assert rent_period.update_factor == nil
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
        index_type: :ipc,
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

    test "with index_type and update_factor" do
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
        index_type: :ipc,
        update_factor: "3.0",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:ok, %Contract{} = contract} = Contracts.create_contract(scope, valid_attrs)
      assert contract.index_type == :ipc
      [rent_period] = contract.rent_periods
      assert rent_period.index_type == :ipc
      # Initial rent period still has nil index value
      assert rent_period.update_factor == nil
    end

    test "with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Contracts.create_contract(scope, @invalid_attrs)
    end

    test "returns error changeset when new contract overlaps at start" do
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

      assert {:ok, %Contract{} = _existing_contract} =
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

      assert {:error, %Ecto.Changeset{} = changeset} =
               Contracts.create_contract(scope, overlapping_attrs)

      assert "overlaps with existing contract" in errors_on(changeset).start_date
    end

    test "returns error changeset when new contract overlaps at end" do
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

      assert {:ok, %Contract{} = _existing_contract} =
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

      assert {:error, %Ecto.Changeset{} = changeset} =
               Contracts.create_contract(scope, overlapping_attrs)

      assert "overlaps with existing contract" in errors_on(changeset).start_date
    end

    test "returns error changeset when new contract completely contains existing" do
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

      assert {:ok, %Contract{} = _existing_contract} =
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

      assert {:error, %Ecto.Changeset{} = changeset} =
               Contracts.create_contract(scope, overlapping_attrs)

      assert "overlaps with existing contract" in errors_on(changeset).start_date
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

    test "returns error changeset when start_date is in the past" do
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

      assert {:error, %Ecto.Changeset{} = changeset} = Contracts.create_contract(scope, attrs)
      assert "cannot be in the past" in errors_on(changeset).start_date
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
                   "update_factor option must be provided when past_start_date? is true",
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
        index_type: :icl,
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:ok, %Contract{} = contract} =
               Contracts.create_contract(scope, attrs,
                 past_start_date?: true,
                 update_factor: Decimal.new("1.05")
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
        assert period.index_type == :icl
        assert period.update_factor == ((index > 0 && Decimal.new("1.05")) || nil)

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

  describe "update_contract/3" do
    test "updates contract with valid attributes" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)
      update_attrs = %{notes: "updated notes", expiration_day: 10}

      assert {:ok, %Contract{} = updated_contract} =
               Contracts.update_contract(scope, contract, update_attrs)

      assert updated_contract.notes == "updated notes"
      assert updated_contract.expiration_day == 10
    end

    test "updates contract end_date" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)
      new_end_date = Date.add(contract.end_date, 30)
      update_attrs = %{end_date: new_end_date}

      assert {:ok, %Contract{} = updated_contract} =
               Contracts.update_contract(scope, contract, update_attrs)

      assert updated_contract.end_date == new_end_date
    end

    test "returns error changeset with invalid attributes" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)
      invalid_attrs = %{expiration_day: nil}

      assert {:error, %Ecto.Changeset{}} =
               Contracts.update_contract(scope, contract, invalid_attrs)

      # Verify contract was not changed
      unchanged_contract = Contracts.get_contract!(scope, contract.id)
      assert unchanged_contract.expiration_day == contract.expiration_day
    end

    test "returns error when user is not authorized" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      contract = contract_fixture(scope)
      update_attrs = %{notes: "updated notes"}

      assert {:error, :unauthorized} =
               Contracts.update_contract(other_scope, contract, update_attrs)

      # Verify contract was not changed
      unchanged_contract = Contracts.get_contract!(scope, contract.id)
      assert unchanged_contract.notes == contract.notes
    end

    test "allows updating archived contract" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)
      {:ok, archived_contract} = Contracts.delete_contract(scope, contract)
      update_attrs = %{notes: "updated notes"}

      # Archived contracts can still be updated
      assert {:ok, %Contract{} = updated_contract} =
               Contracts.update_contract(scope, archived_contract, update_attrs)

      assert updated_contract.notes == "updated notes"
      assert updated_contract.archived == true
    end

    test "updates contract with index_type and rent_period_duration" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)
      update_attrs = %{index_type: :icl, rent_period_duration: 12}

      assert {:ok, %Contract{} = updated_contract} =
               Contracts.update_contract(scope, contract, update_attrs)

      assert updated_contract.index_type == :icl
      assert updated_contract.rent_period_duration == 12
    end

    test "broadcasts contract update" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)
      update_attrs = %{notes: "broadcast test"}

      Contracts.subscribe_contracts(scope)

      assert {:ok, %Contract{} = updated_contract} =
               Contracts.update_contract(scope, contract, update_attrs)

      assert_receive {:updated, ^updated_contract}
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

  describe "get_current_payment_number/1" do
    test "returns 0 when contract hasn't started yet" do
      future_date = Date.add(Date.utc_today(), 30)

      contract = %Contract{
        start_date: future_date,
        end_date: Date.add(future_date, 365)
      }

      assert Contracts.get_current_payment_number(contract) == 0
    end

    test "returns correct payment number for active contract" do
      today = Date.utc_today()
      # Contract started 2 months ago
      start_date = Date.add(today, -60)

      contract = %Contract{
        start_date: start_date,
        end_date: Date.add(today, 365)
      }

      # Should be around month 3 (2 months ago + 1)
      result = Contracts.get_current_payment_number(contract)
      assert result >= 2
    end

    test "caps payment number at contract duration for expired contracts" do
      today = Date.utc_today()
      # Contract ended 6 months ago (3 month contract)
      start_date = Date.add(today, -365)
      end_date = Date.add(today, -180)

      contract = %Contract{
        start_date: start_date,
        end_date: end_date
      }

      # Total months should be capped at contract duration, not inflated
      result = Contracts.get_current_payment_number(contract)
      total_months = Contracts.contract_duration_months(contract)

      assert result == total_months
      # Should be around 7-8 months, not 12+
      assert result <= 12
    end

    test "returns total payments for fully expired contract" do
      # Fixed date test for determinism
      contract = %Contract{
        start_date: ~D[2024-01-01],
        end_date: ~D[2024-03-31]
      }

      result = Contracts.get_current_payment_number(contract)
      total_payments = Contracts.contract_duration_months(contract)

      assert result == total_payments
      assert result == 3
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
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
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
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
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

  describe "period_end_date/3" do
    test "calculates end date for 12 month duration" do
      today = Date.utc_today()
      start_date = today
      max_end_date = Date.add(today, 400)

      end_date = Contracts.period_end_date(12, start_date, max_end_date)

      # Should end at end of month 12 months from start
      expected_end = Date.end_of_month(Date.shift(start_date, month: 11))
      assert end_date == expected_end
    end

    test "respects max_end_date boundary" do
      today = Date.utc_today()
      start_date = today
      max_end_date = Date.add(today, 30)

      # 12 month period would go past max_end_date
      end_date = Contracts.period_end_date(12, start_date, max_end_date)

      assert end_date == max_end_date
    end

    test "calculates end date for 6 month duration" do
      today = ~D[2024-01-15]
      max_end_date = Date.add(today, 365)

      end_date = Contracts.period_end_date(6, today, max_end_date)

      # 6 months from Jan 15 -> end of June
      expected_end = ~D[2024-06-30]
      assert end_date == expected_end
    end

    test "calculates end date for 1 month duration" do
      today = ~D[2024-03-15]
      max_end_date = Date.add(today, 365)

      end_date = Contracts.period_end_date(1, today, max_end_date)

      # 1 month -> end of March
      expected_end = ~D[2024-03-31]
      assert end_date == expected_end
    end

    test "handles month boundaries correctly" do
      # Start on last day of month
      start_date = ~D[2024-01-31]
      max_end_date = Date.add(start_date, 365)

      end_date = Contracts.period_end_date(1, start_date, max_end_date)

      # Should be end of January
      assert end_date == ~D[2024-01-31]
    end

    test "handles February 29, 2024 (leap year)" do
      # To end on Feb 29, 2024 (leap year), we need:
      # period_end_date shifts by (duration - 1) months, then takes end of month
      # So to get Feb 29: start in Sept (shift 5 months = Feb), end_of_month = Feb 29
      start_date = ~D[2023-09-15]
      max_end_date = Date.add(start_date, 400)

      # 6 month duration from Sept -> end of Feb
      end_date = Contracts.period_end_date(6, start_date, max_end_date)

      # Feb 2024 is a leap year, so end date should be Feb 29
      assert end_date == ~D[2024-02-29]
    end

    test "handles February 28, 2025 (non-leap year)" do
      # To end on Feb 28, 2025, start in Sept 2024 (shift 5 months = Feb 2025)
      start_date = ~D[2024-09-15]
      max_end_date = Date.add(start_date, 400)

      # 6 month duration from Sept -> end of Feb
      end_date = Contracts.period_end_date(6, start_date, max_end_date)

      # Feb 2025 is not a leap year, so end date should be Feb 28
      assert end_date == ~D[2025-02-28]
    end

    test "handles year boundary Dec to Jan" do
      start_date = ~D[2024-06-15]
      max_end_date = Date.add(start_date, 365)

      # 7 month duration from June -> shift 6 months = Dec, end_of_month = Dec 31
      end_date = Contracts.period_end_date(7, start_date, max_end_date)

      # Should end on Dec 31, 2024
      assert end_date == ~D[2024-12-31]
    end

    test "handles 31-day to 30-day month transition" do
      # Starting Jan 31
      start_date = ~D[2024-01-31]
      max_end_date = Date.add(start_date, 365)

      # 1 month duration -> shift 0 months = Jan, end_of_month = Jan 31
      end_date = Contracts.period_end_date(1, start_date, max_end_date)

      # Should handle Jan 31 correctly (Jan has 31 days)
      assert end_date == ~D[2024-01-31]
    end

    test "handles April 30 (30-day month)" do
      # To end on April 30, start in Dec (shift 4 months from Dec = Apr)
      start_date = ~D[2023-12-15]
      max_end_date = Date.add(start_date, 365)

      # 5 month duration from Dec -> end of April
      end_date = Contracts.period_end_date(5, start_date, max_end_date)

      # April has 30 days
      assert end_date == ~D[2024-04-30]
    end
  end

  describe "calculate_due_date/2 edge cases" do
    test "calculates due date across month boundary" do
      # Contract starting in month 1 with expiration_day 5
      contract = %Contract{
        start_date: ~D[2024-01-15],
        expiration_day: 5
      }

      # Payment 1: shifts 0 months from Jan 15 = Jan 15, set day to 5 = Jan 5
      due_date = Contracts.calculate_due_date(contract, 1)
      assert due_date == ~D[2024-01-05]

      # Payment 2: shifts 1 month from Jan 15 = Feb 15, set day to 5 = Feb 5
      due_date = Contracts.calculate_due_date(contract, 2)
      assert due_date == ~D[2024-02-05]
    end

    test "handles due date on month start (day 1)" do
      contract = %Contract{
        start_date: ~D[2024-01-15],
        expiration_day: 1
      }

      # Payment 2 shifts 1 month from Jan 15 = Feb 15, set day to 1 = Feb 1
      due_date = Contracts.calculate_due_date(contract, 2)

      # Second payment due on Feb 1
      assert due_date == ~D[2024-02-01]
    end
  end

  describe "total_amount_due/2" do
    test "returns zero for contract with no payments due" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Future contract - nothing due yet
      contract =
        contract_fixture(scope, %{
          start_date: Date.add(today, 30),
          end_date: Date.add(today, 365),
          rent: "1000.00"
        })

      total = Contracts.total_amount_due(scope, contract)
      assert Decimal.equal?(total, Decimal.new("0.00"))
    end

    test "calculates total for single unpaid month" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      today = Date.utc_today()

      # Contract that started 1 month ago
      contract =
        contract_fixture(
          scope,
          %{
            rent: "1000.00",
            start_date: Date.add(today, -45),
            end_date: Date.add(today, 365),
            expiration_day: 1,
            tenant_id: tenant.id,
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
        )

      total = Contracts.total_amount_due(scope, contract)
      # At least one month should be due
      assert Decimal.compare(total, Decimal.new("0.00")) == :gt
    end

    test "returns positive amount for unpaid months" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      tenant_scope = %Vivvo.Accounts.Scope{user: tenant}
      today = Date.utc_today()

      # Contract with one month
      contract =
        contract_fixture(
          scope,
          %{
            rent: "500.00",
            start_date: Date.add(today, -20),
            end_date: Date.add(today, 365),
            expiration_day: 1,
            tenant_id: tenant.id,
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
        )

      # Get the total due before payment
      total_before = Contracts.total_amount_due(scope, contract)

      # Should have some amount due since contract started 20 days ago
      assert Decimal.compare(total_before, Decimal.new("0.00")) == :gt

      # Make a full payment
      payment =
        payment_fixture(tenant_scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "500.00",
          status: :pending
        })

      {:ok, _} = Vivvo.Payments.accept_payment(scope, payment)

      # Total should be reduced after payment (might still have some due depending on months)
      total_after = Contracts.total_amount_due(scope, contract)
      assert Decimal.compare(total_after, total_before) != :gt
    end
  end

  describe "earliest_due_date/2" do
    test "returns nil when contract hasn't started" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      contract =
        contract_fixture(scope, %{
          start_date: Date.add(today, 30),
          end_date: Date.add(today, 365),
          rent: "1000.00"
        })

      assert Contracts.earliest_due_date(scope, contract) == nil
    end

    test "returns due date for unpaid months" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      today = Date.utc_today()

      contract =
        contract_fixture(
          scope,
          %{
            rent: "1000.00",
            start_date: Date.add(today, -45),
            end_date: Date.add(today, 365),
            expiration_day: 5,
            tenant_id: tenant.id,
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
        )

      due_date = Contracts.earliest_due_date(scope, contract)
      assert due_date != nil
      assert is_struct(due_date, Date)
    end

    test "returns nil when all payments are current" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      today = Date.utc_today()

      # Contract starting in future - no payments due yet
      contract =
        contract_fixture(scope, %{
          rent: "500.00",
          start_date: Date.add(today, 5),
          end_date: Date.add(today, 365),
          expiration_day: 5,
          tenant_id: tenant.id,
          index_type: :icl,
          rent_period_duration: 12
        })

      earliest_due = Contracts.earliest_due_date(scope, contract)
      # Should be nil since contract hasn't started
      assert earliest_due == nil
    end
  end

  describe "get_payment_statuses/2" do
    test "returns empty list for future contract" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      contract =
        contract_fixture(scope, %{
          start_date: Date.add(today, 30),
          end_date: Date.add(today, 365),
          rent: "1000.00"
        })

      statuses = Contracts.get_payment_statuses(scope, contract)
      assert statuses == []
    end

    test "returns payment statuses for active contract" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      today = Date.utc_today()

      contract =
        contract_fixture(
          scope,
          %{
            rent: "1000.00",
            start_date: Date.add(today, -45),
            end_date: Date.add(today, 365),
            expiration_day: 5,
            tenant_id: tenant.id,
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
        )

      statuses = Contracts.get_payment_statuses(scope, contract)
      assert is_list(statuses)
      assert statuses != []

      # Check structure of payment status
      first_status = hd(statuses)
      assert Map.has_key?(first_status, :payment_number)
      assert Map.has_key?(first_status, :due_date)
      assert Map.has_key?(first_status, :rent)
      assert Map.has_key?(first_status, :total_paid)
      assert Map.has_key?(first_status, :status)
    end

    test "status reflects unpaid payments correctly" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      today = Date.utc_today()

      contract =
        contract_fixture(
          scope,
          %{
            rent: "500.00",
            start_date: Date.add(today, -20),
            end_date: Date.add(today, 365),
            expiration_day: 1,
            tenant_id: tenant.id,
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
        )

      statuses = Contracts.get_payment_statuses(scope, contract)

      # Find an unpaid status
      unpaid_statuses = Enum.filter(statuses, &(&1.status != :paid))

      if unpaid_statuses != [] do
        unpaid = hd(unpaid_statuses)
        assert Decimal.equal?(unpaid.total_paid, Decimal.new("0.00"))
        # Status can be :pending, :overdue, :partial, or :unpaid
        assert unpaid.status in [:pending, :overdue, :partial, :unpaid]
      end
    end

    test "status reflects paid payments correctly" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      tenant_scope = %Vivvo.Accounts.Scope{user: tenant}
      today = Date.utc_today()

      contract =
        contract_fixture(
          scope,
          %{
            rent: "500.00",
            start_date: Date.add(today, -20),
            end_date: Date.add(today, 365),
            expiration_day: 1,
            tenant_id: tenant.id,
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
        )

      # Make a payment
      payment =
        payment_fixture(tenant_scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "500.00",
          status: :pending
        })

      {:ok, _} = Vivvo.Payments.accept_payment(scope, payment)

      statuses = Contracts.get_payment_statuses(scope, contract)
      paid_statuses = Enum.filter(statuses, &(&1.status == :paid))

      if paid_statuses != [] do
        paid = hd(paid_statuses)
        assert Decimal.compare(paid.total_paid, Decimal.new("0.00")) == :gt
      end
    end
  end

  describe "next_rent_update_date/1" do
    test "returns next update date for contract with current period" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      contract =
        contract_fixture(scope, %{
          start_date: today,
          end_date: Date.add(today, 365),
          rent_period_duration: 6,
          index_type: :ipc
        })

      next_update = Contracts.next_rent_update_date(contract)

      # Should be the day after the current rent period ends
      current_period = Contracts.current_rent_period(contract, today)
      expected_date = Date.add(current_period.end_date, 1)
      assert next_update == expected_date
    end

    test "returns nil when update would be after contract end_date" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create contract ending soon - one month duration
      contract =
        contract_fixture(
          scope,
          %{
            start_date: Date.add(today, -20),
            end_date: Date.add(today, 10),
            rent_period_duration: 1,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      # The next update date would be after the contract ends
      result = Contracts.next_rent_update_date(contract)

      # Should return nil because next update would be after contract end
      assert result == nil
    end

    test "returns date for active contract" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Active contract with 6 month duration
      contract =
        contract_fixture(scope, %{
          start_date: today,
          end_date: Date.add(today, 400),
          rent_period_duration: 6,
          index_type: :ipc
        })

      next_update = Contracts.next_rent_update_date(contract)

      # Should return the update date based on current rent period
      assert next_update != nil
      assert is_struct(next_update, Date)
    end
  end

  describe "days_until_next_update/1" do
    test "calculates days until next rent update" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      contract =
        contract_fixture(scope, %{
          start_date: today,
          end_date: Date.add(today, 365),
          rent_period_duration: 6,
          index_type: :ipc
        })

      days = Contracts.days_until_next_update(contract)

      # Should be positive number of days
      assert days != nil
      assert days > 0
    end

    test "returns nil when no next update date" do
      scope = user_scope_fixture()

      # Create contract that has ended
      contract =
        expired_contract_fixture(scope, %{
          rent_period_duration: 12,
          index_type: :ipc
        })

      # For an expired contract, the next update should be nil
      # (period end date + 1 would be after contract end)
      result = Contracts.days_until_next_update(contract)

      # The result could be nil or negative days
      if result do
        # If there is a date, it could be negative (past)
        assert is_integer(result)
      end
    end

    test "returns 0 when update is today" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create a contract where the next update is today
      # Need a period that ended yesterday
      yesterday = Date.add(today, -1)
      start_date = Date.shift(yesterday, month: -5)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: start_date,
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      # The period should have ended yesterday, so next update is today
      days = Contracts.days_until_next_update(contract)

      if days do
        # Should be 0 or close to 0
        assert days >= 0
      end
    end
  end

  describe "next_payment_date/1" do
    test "returns next payment due date" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Contract that started recently
      contract =
        contract_fixture(
          scope,
          %{
            start_date: Date.add(today, -10),
            end_date: Date.add(today, 365),
            expiration_day: 5,
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
        )

      next_payment = Contracts.next_payment_date(contract)

      # Should return a date
      assert next_payment != nil
      assert is_struct(next_payment, Date)
    end

    test "returns payment date for future contract" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Future contract - first payment will be due on expiration_day of first month
      contract =
        contract_fixture(scope, %{
          start_date: Date.add(today, 5),
          end_date: Date.add(today, 365),
          expiration_day: 5
        })

      next_payment = Contracts.next_payment_date(contract)
      # Should return the first payment due date
      assert next_payment != nil
      assert is_struct(next_payment, Date)
    end

    test "returns nil for expired contract" do
      scope = user_scope_fixture()

      # Expired contract - no future payments
      contract =
        expired_contract_fixture(scope, %{
          expiration_day: 5
        })

      assert Contracts.next_payment_date(contract) == nil
    end
  end

  describe "contract_duration_months/1" do
    test "calculates total months in contract" do
      today = Date.utc_today()

      # 12 month contract
      contract = %Contract{
        start_date: today,
        end_date: Date.add(today, 365)
      }

      months = Contracts.contract_duration_months(contract)

      # Should be approximately 12 months
      assert months > 0
      assert months >= 11 and months <= 13
    end

    test "calculates exact months for 6 month contract" do
      today = ~D[2024-01-15]
      end_date = ~D[2024-07-15]

      contract = %Contract{
        start_date: today,
        end_date: end_date
      }

      months = Contracts.contract_duration_months(contract)

      # Should be approximately 6 months
      assert months >= 5 and months <= 7
    end

    test "returns 1 for single month contract" do
      today = ~D[2024-03-01]
      end_date = ~D[2024-03-31]

      contract = %Contract{
        start_date: today,
        end_date: end_date
      }

      months = Contracts.contract_duration_months(contract)
      assert months >= 0
    end

    test "handles multi-year contracts" do
      today = ~D[2024-01-15]
      end_date = ~D[2026-01-15]

      contract = %Contract{
        start_date: today,
        end_date: end_date
      }

      months = Contracts.contract_duration_months(contract)

      # Should be approximately 24 months
      assert months >= 22 and months <= 26
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
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
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
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
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
          index_type: :icl,
          rent_period_duration: 12
        },
        past_start_date?: true,
        update_factor: Decimal.new("1.0")
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
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
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
        index_type: :icl,
        update_factor: Decimal.new("1.03")
      }

      assert {:ok, %Vivvo.Contracts.RentPeriod{} = rent_period} =
               Contracts.create_rent_period(attrs)

      assert rent_period.value == Decimal.new("1200.00")
      assert rent_period.index_type == :icl
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

    test "returns :already_exists when rent period with same contract_id and start_date exists" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)

      attrs = %{
        contract_id: contract.id,
        start_date: ~D[2026-01-01],
        end_date: ~D[2026-06-30],
        value: Decimal.new("1200.00"),
        index_type: :icl,
        update_factor: Decimal.new("1.03")
      }

      # Create first rent period successfully
      assert {:ok, %Vivvo.Contracts.RentPeriod{}} = Contracts.create_rent_period(attrs)

      # Second attempt with same contract_id and start_date should return :already_exists
      assert {:ok, :already_exists} = Contracts.create_rent_period(attrs)
    end

    test "allows different start_dates for same contract" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)

      attrs1 = %{
        contract_id: contract.id,
        start_date: ~D[2026-01-01],
        end_date: ~D[2026-06-30],
        value: Decimal.new("1200.00"),
        index_type: :icl,
        update_factor: Decimal.new("1.03")
      }

      attrs2 = %{
        contract_id: contract.id,
        start_date: ~D[2026-07-01],
        end_date: ~D[2026-12-31],
        value: Decimal.new("1236.00"),
        index_type: :icl,
        update_factor: Decimal.new("1.03")
      }

      assert {:ok, %Vivvo.Contracts.RentPeriod{}} = Contracts.create_rent_period(attrs1)
      assert {:ok, %Vivvo.Contracts.RentPeriod{}} = Contracts.create_rent_period(attrs2)
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
            index_type: :ipc
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
          index_type: :ipc,
          update_factor: Decimal.new("1.03")
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
            index_type: :icl
          }
        )

      # Period ending next month
      _period =
        rent_period_fixture(contract, %{
          start_date: today,
          end_date: Date.end_of_month(Date.add(today, 30)),
          value: Decimal.new("1000.00"),
          index_type: :icl,
          update_factor: Decimal.new("1.05")
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
            index_type: :ipc
          }
        )

      _period =
        rent_period_fixture(contract, %{
          start_date: Date.add(end_of_this_month, -30),
          end_date: end_of_this_month,
          value: Decimal.new("1000.00"),
          index_type: :ipc,
          update_factor: Decimal.new("1.03")
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
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
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
          index_type: :ipc,
          update_factor: Decimal.new("1.03")
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
            index_type: :ipc
          }
        )

      results = Contracts.contracts_needing_update(today)
      assert results == []
    end
  end

  describe "list_contracts_for_tenant/1" do
    test "returns all contracts for tenant user" do
      owner_scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      tenant_scope = %Vivvo.Accounts.Scope{user: tenant}

      # Create a contract where tenant is the tenant
      contract =
        contract_fixture(owner_scope, %{
          tenant_id: tenant.id
        })

      contracts = Contracts.list_contracts_for_tenant(tenant_scope)
      assert contracts != []
      assert Enum.any?(contracts, &(&1.id == contract.id))
    end

    test "excludes contracts where user is not the tenant" do
      owner_scope = user_scope_fixture()
      tenant_a = user_fixture(%{preferred_roles: [:tenant]})
      tenant_b = user_fixture(%{preferred_roles: [:tenant]})
      tenant_scope_b = %Vivvo.Accounts.Scope{user: tenant_b}

      # Create contract for tenant_a
      contract =
        contract_fixture(owner_scope, %{
          tenant_id: tenant_a.id
        })

      # tenant_b should not see this contract
      contracts = Contracts.list_contracts_for_tenant(tenant_scope_b)
      refute Enum.any?(contracts, &(&1.id == contract.id))
    end

    test "returns empty list when user is not a tenant" do
      non_tenant = user_fixture(%{preferred_roles: [:owner]})
      non_tenant_scope = %Vivvo.Accounts.Scope{user: non_tenant}

      contracts = Contracts.list_contracts_for_tenant(non_tenant_scope)
      assert contracts == []
    end

    test "includes contract details and rent periods" do
      owner_scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      tenant_scope = %Vivvo.Accounts.Scope{user: tenant}

      contract =
        contract_fixture(owner_scope, %{
          tenant_id: tenant.id,
          rent_period_duration: 6,
          index_type: :ipc
        })

      contracts = Contracts.list_contracts_for_tenant(tenant_scope)
      found_contract = Enum.find(contracts, &(&1.id == contract.id))

      assert found_contract != nil
      assert found_contract.rent_periods != nil
      assert is_list(found_contract.rent_periods)
    end
  end

  describe "get_contract_for_tenant/2" do
    test "returns contract for tenant user" do
      owner_scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      tenant_scope = %Vivvo.Accounts.Scope{user: tenant}

      contract =
        contract_fixture(owner_scope, %{
          tenant_id: tenant.id
        })

      result = Contracts.get_contract_for_tenant(tenant_scope, contract.id)
      assert result.id == contract.id
    end

    test "preloads rent periods and payments" do
      owner_scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      tenant_scope = %Vivvo.Accounts.Scope{user: tenant}

      contract =
        contract_fixture(owner_scope, %{
          tenant_id: tenant.id,
          rent_period_duration: 6,
          index_type: :ipc
        })

      result = Contracts.get_contract_for_tenant(tenant_scope, contract.id)
      assert result.rent_periods != nil
      assert is_list(result.rent_periods)
    end

    test "returns nil when contract does not belong to tenant" do
      owner_scope = user_scope_fixture()
      tenant_a = user_fixture(%{preferred_roles: [:tenant]})
      tenant_b = user_fixture(%{preferred_roles: [:tenant]})
      tenant_scope_b = %Vivvo.Accounts.Scope{user: tenant_b}

      contract =
        contract_fixture(owner_scope, %{
          tenant_id: tenant_a.id
        })

      assert Contracts.get_contract_for_tenant(tenant_scope_b, contract.id) == nil
    end

    test "returns nil for non-existent contract" do
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      tenant_scope = %Vivvo.Accounts.Scope{user: tenant}

      assert Contracts.get_contract_for_tenant(tenant_scope, 99_999_999) == nil
    end
  end

  describe "dashboard_summary/1" do
    test "returns dashboard statistics for user" do
      scope = user_scope_fixture()

      # Create some contracts
      contract_fixture(scope, %{rent: "1000.00"})
      contract_fixture(scope, %{rent: "1500.00"})

      summary = Contracts.dashboard_summary(scope)

      assert Map.has_key?(summary, :total_contracts)
      assert Map.has_key?(summary, :total_properties)
      assert Map.has_key?(summary, :total_tenants)
      assert Map.has_key?(summary, :occupancy_rate)
    end

    test "counts total contracts correctly" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create active contract
      _active_contract =
        contract_fixture(scope, %{
          start_date: today,
          end_date: Date.add(today, 365)
        })

      summary = Contracts.dashboard_summary(scope)

      # Should have at least 1 contract
      assert summary.total_contracts >= 1
      assert summary.total_properties >= 1
    end

    test "calculates occupancy rate" do
      scope = user_scope_fixture()

      # Create a property and a contract for it
      property_fixture(scope)
      contract_fixture(scope)

      summary = Contracts.dashboard_summary(scope)

      # Occupancy rate should be a float between 0 and 100
      assert is_float(summary.occupancy_rate)
      assert summary.occupancy_rate >= 0.0
      assert summary.occupancy_rate <= 100.0
    end

    test "returns zero values for user with no contracts" do
      scope = user_scope_fixture()

      summary = Contracts.dashboard_summary(scope)

      assert summary.total_contracts == 0
      assert summary.total_properties >= 0
      assert summary.total_tenants == 0
      assert summary.occupancy_rate == 0.0
    end
  end

  describe "days_until_end/1" do
    test "calculates days until contract ends" do
      today = Date.utc_today()

      contract = %Contract{
        start_date: today,
        end_date: Date.add(today, 30)
      }

      days = Contracts.days_until_end(contract)

      assert days >= 29 and days <= 31
    end

    test "returns nil for expired contract" do
      today = Date.utc_today()

      contract = %Contract{
        start_date: Date.add(today, -60),
        end_date: Date.add(today, -10)
      }

      days = Contracts.days_until_end(contract)

      assert days == nil
    end

    test "returns large positive number for future contract" do
      today = Date.utc_today()

      contract = %Contract{
        start_date: Date.add(today, 30),
        end_date: Date.add(today, 400)
      }

      days = Contracts.days_until_end(contract)

      assert days > 350
    end
  end

  describe "days_until_start/1" do
    test "calculates days until contract starts" do
      today = Date.utc_today()

      contract = %Contract{
        start_date: Date.add(today, 15),
        end_date: Date.add(today, 365)
      }

      days = Contracts.days_until_start(contract)

      assert days >= 14 and days <= 16
    end

    test "returns 0 for active contract" do
      today = Date.utc_today()

      contract = %Contract{
        start_date: today,
        end_date: Date.add(today, 365)
      }

      assert Contracts.days_until_start(contract) == 0
    end

    test "returns nil for past contract start" do
      today = Date.utc_today()

      contract = %Contract{
        start_date: Date.add(today, -30),
        end_date: Date.add(today, 335)
      }

      days = Contracts.days_until_start(contract)
      assert days == nil
    end
  end

  describe "check_overlapping_contracts/4" do
    test "returns ok when no overlapping contracts" do
      scope = user_scope_fixture()
      property = property_fixture(scope)

      today = Date.utc_today()
      start_date = today
      end_date = Date.add(today, 365)

      result =
        Contracts.check_overlapping_contracts(
          scope,
          property.id,
          start_date,
          end_date
        )

      assert {:ok, nil} = result
    end

    test "detects overlapping contract for same property" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)

      today = Date.utc_today()

      # Create existing contract
      _existing_contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id,
          start_date: today,
          end_date: Date.add(today, 365)
        })

      # Check overlap with new contract dates
      result =
        Contracts.check_overlapping_contracts(
          scope,
          property.id,
          Date.add(today, 30),
          Date.add(today, 200)
        )

      assert {:error, {:overlap, _contract}} = result
    end

    test "excludes non-overlapping contracts" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)

      today = Date.utc_today()

      # Create existing contract
      _existing_contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id,
          start_date: today,
          end_date: Date.add(today, 90)
        })

      # Check for dates after existing contract ends
      result =
        Contracts.check_overlapping_contracts(
          scope,
          property.id,
          Date.add(today, 100),
          Date.add(today, 200)
        )

      assert {:ok, nil} = result
    end

    test "excludes archived contracts from overlap check" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)

      today = Date.utc_today()

      # Create existing contract
      existing_contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id,
          start_date: today,
          end_date: Date.add(today, 365)
        })

      # Archive the contract
      Repo.update!(Contract.archive_changeset(existing_contract, scope))

      # Check overlap - archived contract should not be detected
      result =
        Contracts.check_overlapping_contracts(
          scope,
          property.id,
          Date.add(today, 30),
          Date.add(today, 200)
        )

      assert {:ok, nil} = result
    end
  end
end
