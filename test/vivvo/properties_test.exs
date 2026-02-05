defmodule Vivvo.PropertiesTest do
  use Vivvo.DataCase

  alias Vivvo.Properties

  describe "properties" do
    alias Vivvo.Properties.Property

    import Vivvo.AccountsFixtures, only: [user_scope_fixture: 0]
    import Vivvo.PropertiesFixtures

    @invalid_attrs %{name: nil, address: nil, area: nil, rooms: nil, notes: nil}

    test "list_properties/1 returns all scoped properties" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      property = property_fixture(scope)
      other_property = property_fixture(other_scope)
      assert Properties.list_properties(scope) == [property]
      assert Properties.list_properties(other_scope) == [other_property]
    end

    test "get_property!/2 returns the property with given id" do
      scope = user_scope_fixture()
      property = property_fixture(scope)
      other_scope = user_scope_fixture()
      assert Properties.get_property!(scope, property.id) == property

      assert_raise Ecto.NoResultsError, fn ->
        Properties.get_property!(other_scope, property.id)
      end
    end

    test "create_property/2 with valid data creates a property" do
      valid_attrs = %{
        name: "some name",
        address: "some address",
        area: 42,
        rooms: 42,
        notes: "some notes"
      }

      scope = user_scope_fixture()

      assert {:ok, %Property{} = property} = Properties.create_property(scope, valid_attrs)
      assert property.name == "some name"
      assert property.address == "some address"
      assert property.area == 42
      assert property.rooms == 42
      assert property.notes == "some notes"
      assert property.user_id == scope.user.id
    end

    test "create_property/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Properties.create_property(scope, @invalid_attrs)
    end

    test "update_property/3 with valid data updates the property" do
      scope = user_scope_fixture()
      property = property_fixture(scope)

      update_attrs = %{
        name: "some updated name",
        address: "some updated address",
        area: 43,
        rooms: 43,
        notes: "some updated notes"
      }

      assert {:ok, %Property{} = property} =
               Properties.update_property(scope, property, update_attrs)

      assert property.name == "some updated name"
      assert property.address == "some updated address"
      assert property.area == 43
      assert property.rooms == 43
      assert property.notes == "some updated notes"
    end

    test "update_property/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      property = property_fixture(scope)

      assert_raise MatchError, fn ->
        Properties.update_property(other_scope, property, %{})
      end
    end

    test "update_property/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      property = property_fixture(scope)

      assert {:error, %Ecto.Changeset{}} =
               Properties.update_property(scope, property, @invalid_attrs)

      assert property == Properties.get_property!(scope, property.id)
    end

    test "delete_property/2 deletes the property" do
      scope = user_scope_fixture()
      property = property_fixture(scope)
      assert {:ok, %Property{}} = Properties.delete_property(scope, property)
      assert_raise Ecto.NoResultsError, fn -> Properties.get_property!(scope, property.id) end
    end

    test "delete_property/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      property = property_fixture(scope)
      assert_raise MatchError, fn -> Properties.delete_property(other_scope, property) end
    end

    test "change_property/2 returns a property changeset" do
      scope = user_scope_fixture()
      property = property_fixture(scope)
      assert %Ecto.Changeset{} = Properties.change_property(scope, property)
    end
  end
end
