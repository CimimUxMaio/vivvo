defmodule Vivvo.ContractsTest do
  use Vivvo.DataCase

  alias Vivvo.Contracts
  alias Vivvo.Contracts.Contract

  import Vivvo.AccountsFixtures, only: [user_scope_fixture: 0, user_fixture: 1]
  import Vivvo.ContractsFixtures
  import Vivvo.PaymentsFixtures
  import Vivvo.PropertiesFixtures

  @invalid_attrs %{start_date: nil, end_date: nil, expiration_day: nil, notes: nil, rent: nil}

  describe "list_contracts/1" do
    test "returns all scoped contracts" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      contract = contract_fixture(scope)
      other_contract = contract_fixture(other_scope)
      assert Contracts.list_contracts(scope) == [contract]
      assert Contracts.list_contracts(other_scope) == [other_contract]
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

      assert Contracts.list_contracts(scope) == [active_contract]
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
      assert Contracts.get_contract!(scope, contract.id) == contract

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

      assert Contracts.get_contract!(scope, contract.id) == contract
    end
  end

  describe "get_contract_for_property/2" do
    test "returns active contract for property" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)

      contract =
        contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      result = Contracts.get_contract_for_property(scope, property.id)

      assert result.id == contract.id
      assert result.property_id == property.id
    end

    test "returns nil when no active contract" do
      scope = user_scope_fixture()
      property = property_fixture(scope)

      assert Contracts.get_contract_for_property(scope, property.id) == nil
    end

    test "returns nil when only archived contracts exist" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)

      contract =
        contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      {:ok, _archived} = Contracts.delete_contract(scope, contract)

      assert Contracts.get_contract_for_property(scope, property.id) == nil
    end

    test "preloads tenant association" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)

      contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      result = Contracts.get_contract_for_property(scope, property.id)

      assert result.tenant != nil
      assert result.tenant.id == tenant.id
    end

    test "scoped to current user" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)

      contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      assert Contracts.get_contract_for_property(other_scope, property.id) == nil
    end
  end

  describe "create_contract/2" do
    test "with valid data creates a contract" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)

      valid_attrs = %{
        start_date: ~D[2026-02-04],
        end_date: ~D[2026-03-04],
        expiration_day: 5,
        notes: "some notes",
        rent: "120.5",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:ok, %Contract{} = contract} = Contracts.create_contract(scope, valid_attrs)
      assert contract.start_date == ~D[2026-02-04]
      assert contract.end_date == ~D[2026-03-04]
      assert contract.expiration_day == 5
      assert contract.notes == "some notes"
      assert contract.rent == Decimal.new("120.5")
      assert contract.user_id == scope.user.id
      assert contract.property_id == property.id
      assert contract.tenant_id == tenant.id
    end

    test "with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Contracts.create_contract(scope, @invalid_attrs)
    end

    test "archives existing contract when creating new one for same property" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property = property_fixture(scope)

      old_contract =
        contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      new_attrs = %{
        start_date: ~D[2026-03-01],
        end_date: ~D[2026-04-01],
        expiration_day: 10,
        notes: "new notes",
        rent: "200.0",
        property_id: property.id,
        tenant_id: tenant.id
      }

      assert {:ok, %Contract{} = new_contract} = Contracts.create_contract(scope, new_attrs)

      # Old contract should be archived
      assert_raise Ecto.NoResultsError, fn ->
        Contracts.get_contract!(scope, old_contract.id)
      end

      # New contract should be active
      assert Contracts.get_contract_for_property(scope, property.id).id == new_contract.id

      # Verify old contract is archived in database
      archived =
        Repo.get_by(Contract, id: old_contract.id, user_id: scope.user.id, archived: true)

      assert archived != nil
      assert archived.archived == true
      assert archived.archived_by_id == scope.user.id
    end

    test "only archives contracts for the same property" do
      scope = user_scope_fixture()
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      property1 = property_fixture(scope, %{name: "Property 1"})
      property2 = property_fixture(scope, %{name: "Property 2"})

      contract1 =
        contract_fixture(scope, %{property_id: property1.id, tenant_id: tenant.id})

      contract2 =
        contract_fixture(scope, %{property_id: property2.id, tenant_id: tenant.id})

      # Create new contract for property1
      new_attrs = %{
        start_date: ~D[2026-03-01],
        end_date: ~D[2026-04-01],
        expiration_day: 10,
        notes: "new notes",
        rent: "200.0",
        property_id: property1.id,
        tenant_id: tenant.id
      }

      assert {:ok, _new_contract} = Contracts.create_contract(scope, new_attrs)

      # Contract for property1 should be archived
      assert_raise Ecto.NoResultsError, fn ->
        Contracts.get_contract!(scope, contract1.id)
      end

      # Contract for property2 should still be active
      assert Contracts.get_contract!(scope, contract2.id).id == contract2.id
    end
  end

  describe "update_contract/3" do
    test "with valid data updates the contract" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)

      update_attrs = %{
        start_date: ~D[2026-02-05],
        end_date: ~D[2026-02-10],
        expiration_day: 15,
        notes: "some updated notes",
        rent: "456.7"
      }

      assert {:ok, %Contract{} = contract} =
               Contracts.update_contract(scope, contract, update_attrs)

      assert contract.start_date == ~D[2026-02-05]
      assert contract.end_date == ~D[2026-02-10]
      assert contract.expiration_day == 15
      assert contract.notes == "some updated notes"
      assert contract.rent == Decimal.new("456.7")
    end

    test "with invalid scope returns unauthorized error" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      contract = contract_fixture(scope)

      assert {:error, :unauthorized} = Contracts.update_contract(other_scope, contract, %{})
    end

    test "with invalid data returns error changeset" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope)

      assert {:error, %Ecto.Changeset{}} =
               Contracts.update_contract(scope, contract, @invalid_attrs)

      assert contract == Contracts.get_contract!(scope, contract.id)
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

  describe "payment_overdue?/1" do
    test "returns true when current day > expiration_day" do
      today = Date.utc_today()
      expiration_day = max(today.day - 1, 1)

      contract = %Contract{
        expiration_day: expiration_day
      }

      assert Contracts.payment_overdue?(contract) == true
    end

    test "returns false when current day < expiration_day" do
      today = Date.utc_today()

      # Make sure we have a valid expiration_day
      expiration_day = min(today.day + 1, 20)

      contract = %Contract{
        expiration_day: expiration_day
      }

      assert Contracts.payment_overdue?(contract) == false
    end

    test "returns false when current day = expiration_day" do
      today = Date.utc_today()
      expiration_day = min(today.day, 20)

      contract = %Contract{
        expiration_day: expiration_day
      }

      assert Contracts.payment_overdue?(contract) == false
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

      assert result.first > result.last
    end

    test "includes current payment number when its due date has passed" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      # Contract started 2 months ago, with expiration day 1 (already passed)
      start_date = Date.add(today, -60)

      contract =
        contract_fixture(scope, %{
          start_date: start_date,
          end_date: Date.add(start_date, 365),
          expiration_day: 1
        })

      result = Contracts.get_past_payment_numbers(contract, today)

      # Due date is day 1, today is after that, so both months should be past
      assert Range.size(result) >= 2
      assert result.first == 1
    end

    test "excludes current payment number when its due date hasn't passed" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      # Contract started 2 months ago, with expiration day later in month
      start_date = Date.add(today, -60)
      # Use expiration day later than current day
      expiration_day = min(today.day + 5, 20)

      contract =
        contract_fixture(scope, %{
          start_date: start_date,
          end_date: Date.add(start_date, 365),
          expiration_day: expiration_day
        })

      result = Contracts.get_past_payment_numbers(contract, today)

      # Current month due date hasn't passed yet
      current = Contracts.get_current_payment_number(contract)
      assert result.last == current - 1
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
        contract_fixture(scope, %{
          rent: Decimal.new("1000.00"),
          start_date: Date.add(today, -90),
          end_date: Date.add(today, 365),
          expiration_day: 1,
          tenant_id: tenant_scope.user.id
        })

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
          amount: Decimal.new("1000.00"),
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
          rent: Decimal.new("1000.00"),
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
        contract_fixture(scope, %{
          rent: Decimal.new("500.00"),
          start_date: Date.add(today, -60),
          end_date: Date.add(today, 365),
          expiration_day: 1,
          tenant_id: tenant_scope.user.id
        })

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
            amount: Decimal.new("500.00"),
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
end
