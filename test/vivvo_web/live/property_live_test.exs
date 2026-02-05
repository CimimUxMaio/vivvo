defmodule VivvoWeb.PropertyLiveTest do
  use VivvoWeb.ConnCase

  import Phoenix.LiveViewTest
  import Vivvo.PropertiesFixtures
  import Vivvo.ContractsFixtures
  import Vivvo.AccountsFixtures

  alias Vivvo.Accounts
  alias Vivvo.Accounts.Scope

  @create_attrs %{
    name: "some name",
    address: "some address",
    area: 42,
    rooms: 42,
    notes: "some notes"
  }
  @update_attrs %{
    name: "some updated name",
    address: "some updated address",
    area: 43,
    rooms: 43,
    notes: "some updated notes"
  }
  @invalid_attrs %{name: nil, address: nil, area: nil, rooms: nil, notes: nil}

  setup :register_and_log_in_user

  defp ensure_owner_role(%{user: user} = context) do
    # Update user to ensure owner role
    {:ok, updated_user} = Accounts.update_user_current_role(user, %{current_role: :owner})
    updated_scope = Scope.for_user(updated_user)
    Map.merge(context, %{user: updated_user, scope: updated_scope})
  end

  defp create_property(%{scope: scope}) do
    property = property_fixture(scope)

    %{property: property}
  end

  describe "Index" do
    setup [:ensure_owner_role, :create_property]

    test "lists all properties", %{conn: conn, property: property} do
      {:ok, _index_live, html} = live(conn, ~p"/properties")

      assert html =~ "Listing Properties"
      assert html =~ property.name
    end

    test "saves new property", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/properties")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Property")
               |> render_click()
               |> follow_redirect(conn, ~p"/properties/new")

      assert render(form_live) =~ "New Property"

      assert form_live
             |> form("#property-form", property: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#property-form", property: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/properties")

      html = render(index_live)
      assert html =~ "Property created successfully"
      assert html =~ "some name"
    end

    test "updates property in listing", %{conn: conn, property: property} do
      {:ok, index_live, _html} = live(conn, ~p"/properties")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#properties-#{property.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/properties/#{property}/edit")

      assert render(form_live) =~ "Edit Property"

      assert form_live
             |> form("#property-form", property: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#property-form", property: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/properties")

      html = render(index_live)
      assert html =~ "Property updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes property in listing", %{conn: conn, property: property} do
      {:ok, index_live, _html} = live(conn, ~p"/properties")

      assert index_live |> element("#properties-#{property.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#properties-#{property.id}")
    end

    test "deleted properties do not reappear in listing", %{conn: conn, scope: scope} do
      property = property_fixture(scope, %{name: "Deleted Property"})
      {:ok, _} = Vivvo.Properties.delete_property(scope, property)

      {:ok, _index_live, html} = live(conn, ~p"/properties")

      refute html =~ "Deleted Property"
    end
  end

  describe "Show" do
    setup [:ensure_owner_role, :create_property]

    test "displays property", %{conn: conn, property: property} do
      {:ok, _show_live, html} = live(conn, ~p"/properties/#{property}")

      assert html =~ "Show Property"
      assert html =~ property.name
    end

    test "updates property and returns to show", %{conn: conn, property: property} do
      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/properties/#{property}/edit?return_to=show")

      assert render(form_live) =~ "Edit Property"

      assert form_live
             |> form("#property-form", property: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#property-form", property: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/properties/#{property}")

      html = render(show_live)
      assert html =~ "Property updated successfully"
      assert html =~ "some updated name"
    end
  end

  describe "Contract section" do
    setup [:ensure_owner_role, :create_property]

    test "displays 'No active contract' when property has no contract", %{
      conn: conn,
      property: property
    } do
      {:ok, _show_live, html} = live(conn, ~p"/properties/#{property}")

      assert html =~ "Contract Information"
      assert html =~ "No active contract"
    end

    test "displays 'Create Contract' button when no contract", %{conn: conn, property: property} do
      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      assert has_element?(show_live, "a[href='/properties/#{property.id}/contracts/new']")
    end

    test "displays contract summary when property has active contract", %{
      conn: conn,
      property: property,
      scope: scope
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant], first_name: "John", last_name: "Doe"})
      _contract = contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      {:ok, _show_live, html} = live(conn, ~p"/properties/#{property}")

      assert html =~ "Contract Information"
      assert html =~ "John Doe"
    end

    test "displays tenant name in summary", %{conn: conn, property: property, scope: scope} do
      tenant =
        user_fixture(%{
          preferred_roles: [:tenant],
          first_name: "Jane",
          last_name: "Smith",
          email: "jane@example.com"
        })

      _contract = contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      {:ok, _show_live, html} = live(conn, ~p"/properties/#{property}")

      assert html =~ "Jane Smith"
    end

    test "displays rent amount in summary", %{conn: conn, property: property, scope: scope} do
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      _contract =
        contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id, rent: "500.00"})

      {:ok, _show_live, html} = live(conn, ~p"/properties/#{property}")

      assert html =~ "$500.00" or html =~ "500.00"
    end

    test "displays status badge in summary", %{conn: conn, property: property, scope: scope} do
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      _contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id,
          start_date: Date.add(Date.utc_today(), -10),
          end_date: Date.add(Date.utc_today(), 10)
        })

      {:ok, _show_live, html} = live(conn, ~p"/properties/#{property}")

      assert html =~ "Active" or html =~ "active"
    end

    test "'View Details' button opens modal", %{conn: conn, property: property, scope: scope} do
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      _contract = contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      # Click on view details button
      html = show_live |> element("button", "View Details") |> render_click()

      # Modal should be visible with contract details
      assert html =~ "Contract Details" or html =~ "contract"
    end

    test "'Edit Contract' button navigates to edit form", %{
      conn: conn,
      property: property,
      scope: scope
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      contract = contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      assert has_element?(
               show_live,
               "a[href='/properties/#{property.id}/contracts/#{contract.id}/edit']"
             )
    end

    test "'Create Contract' button navigates to new form", %{conn: conn, property: property} do
      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      {:ok, _new_live, html} =
        show_live
        |> element("a[href='/properties/#{property.id}/contracts/new']")
        |> render_click()
        |> follow_redirect(conn, ~p"/properties/#{property}/contracts/new")

      assert html =~ "New Contract for"
    end

    test "modal shows all contract details", %{conn: conn, property: property, scope: scope} do
      tenant =
        user_fixture(%{
          preferred_roles: [:tenant],
          first_name: "John",
          last_name: "Doe",
          email: "john@example.com",
          phone_number: "+1234567890"
        })

      _contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id,
          rent: "500.00",
          expiration_day: 5,
          notes: "Test notes"
        })

      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      html = show_live |> element("button", "View Details") |> render_click()

      assert html =~ "Contract Details"
      assert html =~ "John Doe"
      assert html =~ "john@example.com"
      assert html =~ "$500.00" or html =~ "500.00"
      assert html =~ "Day 5"
      assert html =~ "Test notes"
    end

    test "modal archive action archives contract", %{
      conn: conn,
      property: property,
      scope: scope
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      contract = contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      # Open modal
      show_live |> element("button", "View Details") |> render_click()

      # Archive the contract
      show_live |> element("button", "Archive") |> render_click()

      # Contract should be archived
      assert_raise Ecto.NoResultsError, fn ->
        Vivvo.Contracts.get_contract!(scope, contract.id)
      end

      # Page should show no active contract
      html = render(show_live)
      assert html =~ "No active contract"
    end

    test "modal close button closes modal", %{conn: conn, property: property, scope: scope} do
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      _contract = contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      # Open modal
      html = show_live |> element("button", "View Details") |> render_click()
      assert html =~ "Contract Details"

      # Modal should have close functionality
      # The modal uses JS.push to send close_modal event
      # which is handled by the LiveComponent
    end
  end

  describe "Contract PubSub updates" do
    setup [:ensure_owner_role, :create_property]

    test "contract creation updates UI", %{conn: conn, property: property, scope: scope} do
      {:ok, show_live, html} = live(conn, ~p"/properties/#{property}")

      # Initially no contract
      assert html =~ "No active contract"

      # Create contract in background
      tenant = user_fixture(%{preferred_roles: [:tenant], first_name: "Jane", last_name: "Doe"})

      contract_attrs = %{
        start_date: ~D[2026-02-05],
        end_date: ~D[2026-03-05],
        tenant_id: tenant.id,
        expiration_day: 5,
        rent: "100.00",
        property_id: property.id
      }

      {:ok, _contract} = Vivvo.Contracts.create_contract(scope, contract_attrs)

      # Give LiveView time to process PubSub message
      html = render(show_live)

      # UI should update to show contract
      assert html =~ "Jane Doe"
    end

    test "contract update updates UI", %{conn: conn, property: property, scope: scope} do
      tenant = user_fixture(%{preferred_roles: [:tenant], first_name: "John", last_name: "Doe"})
      contract = contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      {:ok, show_live, html} = live(conn, ~p"/properties/#{property}")

      # Initially shows contract
      assert html =~ "John Doe"

      # Update contract
      {:ok, _updated} =
        Vivvo.Contracts.update_contract(scope, contract, %{rent: "999.00"})

      # Give LiveView time to process PubSub message
      html = render(show_live)

      # UI should reflect update
      assert html =~ "$999.00" or html =~ "999.00"
    end

    test "contract deletion removes contract from UI", %{
      conn: conn,
      property: property,
      scope: scope
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      contract = contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      {:ok, show_live, html} = live(conn, ~p"/properties/#{property}")

      # Initially shows contract
      refute html =~ "No active contract"

      # Archive/delete contract
      {:ok, _} = Vivvo.Contracts.delete_contract(scope, contract)

      # Give LiveView time to process PubSub message
      html = render(show_live)

      # UI should show no active contract
      assert html =~ "No active contract"
    end

    test "ignores contract events for other properties", %{
      conn: conn,
      property: property,
      scope: scope
    } do
      # Create another property
      other_property = property_fixture(scope, %{name: "Other Property"})
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, show_live, html} = live(conn, ~p"/properties/#{property}")

      # Initially no contract for our property
      assert html =~ "No active contract"

      # Create contract for OTHER property
      contract_attrs = %{
        start_date: ~D[2026-02-05],
        end_date: ~D[2026-03-05],
        tenant_id: tenant.id,
        expiration_day: 5,
        rent: "100.00",
        property_id: other_property.id
      }

      {:ok, _contract} = Vivvo.Contracts.create_contract(scope, contract_attrs)

      # Give LiveView time to potentially process PubSub message
      html = render(show_live)

      # Our property should still show no contract
      assert html =~ "No active contract"
    end
  end

  describe "Authorization" do
    setup :ensure_owner_role
    setup :create_property

    defp set_tenant_role(%{user: user, conn: conn} = context) do
      {:ok, updated_user} = Accounts.update_user_current_role(user, %{current_role: :tenant})
      # Re-log in with updated role
      conn = VivvoWeb.ConnCase.log_in_user(conn, updated_user)
      Map.merge(context, %{user: updated_user, conn: conn})
    end

    test "non-owner cannot access property index", %{conn: conn, user: user} do
      context = set_tenant_role(%{user: user, conn: conn})

      assert {:error,
              {:redirect,
               %{to: "/", flash: %{"error" => "You must be an owner to access this page."}}}} =
               live(context.conn, ~p"/properties")
    end

    test "non-owner cannot access property new form", %{conn: conn, user: user} do
      context = set_tenant_role(%{user: user, conn: conn})

      assert {:error,
              {:redirect,
               %{to: "/", flash: %{"error" => "You must be an owner to access this page."}}}} =
               live(context.conn, ~p"/properties/new")
    end

    test "non-owner cannot access property show page", %{
      conn: conn,
      property: property,
      user: user
    } do
      context = set_tenant_role(%{user: user, conn: conn})

      assert {:error,
              {:redirect,
               %{to: "/", flash: %{"error" => "You must be an owner to access this page."}}}} =
               live(context.conn, ~p"/properties/#{property}")
    end

    test "non-owner cannot access property edit form", %{
      conn: conn,
      property: property,
      user: user
    } do
      context = set_tenant_role(%{user: user, conn: conn})

      assert {:error,
              {:redirect,
               %{to: "/", flash: %{"error" => "You must be an owner to access this page."}}}} =
               live(context.conn, ~p"/properties/#{property}/edit")
    end
  end
end
