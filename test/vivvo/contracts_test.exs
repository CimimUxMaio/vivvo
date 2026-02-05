defmodule Vivvo.ContractsTest do
  use Vivvo.DataCase

  alias Vivvo.Contracts
  alias Vivvo.Contracts.Contract

  import Vivvo.AccountsFixtures, only: [user_scope_fixture: 0, user_fixture: 1]
  import Vivvo.ContractsFixtures
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

    test "with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      contract = contract_fixture(scope)

      assert_raise MatchError, fn ->
        Contracts.update_contract(other_scope, contract, %{})
      end
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

    test "with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      contract = contract_fixture(scope)
      assert_raise MatchError, fn -> Contracts.delete_contract(other_scope, contract) end
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

      contract = %Contract{
        expiration_day: today.day - 1
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

      contract = %Contract{
        expiration_day: today.day
      }

      assert Contracts.payment_overdue?(contract) == false
    end
  end
end
