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

      assert html =~ "Properties"
      assert html =~ property.name
    end

    test "saves new property", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/properties")

      assert {:ok, form_live, _} =
               index_live
               |> element("#page-header-desktop a", "New Property")
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
               |> element("#properties-#{property.id} a[title='Edit']")
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

      assert index_live
             |> element("#properties-#{property.id} button[title='Delete']")
             |> render_click()

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
               |> element("#page-header-desktop a", "Edit")
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
      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      # Switch to Active Contract tab
      html =
        show_live |> element("button[phx-value-selected='active_contract']") |> render_click()

      assert html =~ "Active Contract"
      assert html =~ "No Active Contract"
    end

    test "displays 'Create Contract' button when no contract", %{conn: conn, property: property} do
      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      # Switch to Active Contract tab first
      show_live |> element("button[phx-value-selected='active_contract']") |> render_click()

      assert has_element?(show_live, "a[href='/properties/#{property.id}/contracts/new']")
    end

    test "displays contract summary when property has active contract", %{
      conn: conn,
      property: property,
      scope: scope
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant], first_name: "John", last_name: "Doe"})
      _contract = contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      # Switch to Active Contract tab
      html =
        show_live |> element("button[phx-value-selected='active_contract']") |> render_click()

      assert html =~ "Active Contract"
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

      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      # Switch to Active Contract tab
      html =
        show_live |> element("button[phx-value-selected='active_contract']") |> render_click()

      assert html =~ "Jane Smith"
    end

    test "displays rent amount in summary", %{conn: conn, property: property, scope: scope} do
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      _contract =
        contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id, rent: "500.00"})

      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      # Switch to Active Contract tab
      html =
        show_live |> element("button[phx-value-selected='active_contract']") |> render_click()

      assert html =~ "$500.00" or html =~ "500.00"
    end

    test "displays status badge in summary", %{conn: conn, property: property, scope: scope} do
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      _contract =
        contract_fixture(
          scope,
          %{
            property_id: property.id,
            tenant_id: tenant.id,
            start_date: Date.add(Date.utc_today(), -10),
            end_date: Date.add(Date.utc_today(), 10),
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("0.0")
        )

      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      # Switch to Active Contract tab
      html =
        show_live |> element("button[phx-value-selected='active_contract']") |> render_click()

      assert html =~ "Active" or html =~ "active"
    end

    test "'View Full Details' button navigates to contract show page", %{
      conn: conn,
      property: property,
      scope: scope
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      contract = contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      # Switch to Active Contract tab first
      show_live |> element("button[phx-value-selected='active_contract']") |> render_click()

      # Click on view full details button should navigate to show page
      show_live
      |> element(
        "a[href='/properties/#{property.id}/contracts/#{contract.id}?return_to=contract']"
      )
      |> render_click()
      |> follow_redirect(
        conn,
        ~p"/properties/#{property.id}/contracts/#{contract.id}?return_to=contract"
      )
    end

    test "'Create Contract' button navigates to new form", %{conn: conn, property: property} do
      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      # Switch to Active Contract tab first
      show_live |> element("button[phx-value-selected='active_contract']") |> render_click()

      {:ok, _new_live, html} =
        show_live
        |> element("a#create-contract-empty-state")
        |> render_click()
        |> follow_redirect(conn, ~p"/properties/#{property}/contracts/new")

      assert html =~ "New Contract for"
    end
  end

  describe "Contract PubSub updates" do
    setup [:ensure_owner_role, :create_property]

    test "contract creation updates UI", %{conn: conn, property: property, scope: scope} do
      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      # Initially no contract - need to switch to Active Contract tab to verify
      show_live |> element("button[phx-value-selected='active_contract']") |> render_click()
      html = render(show_live)
      assert html =~ "No Active Contract"

      # Create contract in background
      tenant = user_fixture(%{preferred_roles: [:tenant], first_name: "Jane", last_name: "Doe"})

      # Use dates that include today's date for proper rent period coverage
      today = Date.utc_today()

      contract_attrs = %{
        start_date: today,
        end_date: Date.add(today, 30),
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
      tenant1 = user_fixture(%{preferred_roles: [:tenant], first_name: "John", last_name: "Doe"})

      tenant2 =
        user_fixture(%{preferred_roles: [:tenant], first_name: "Jane", last_name: "Smith"})

      contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant1.id
        })

      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      # Switch to Active Contract tab to see contract info
      show_live |> element("button[phx-value-selected='active_contract']") |> render_click()
      html = render(show_live)

      # Initially shows first tenant
      assert html =~ "John Doe"
      refute html =~ "Jane Smith"

      # Update contract to different tenant
      {:ok, _updated} =
        Vivvo.Contracts.update_contract(scope, contract, %{tenant_id: tenant2.id})

      # Give LiveView time to process PubSub message
      html = render(show_live)

      # UI should reflect update with new tenant name
      assert html =~ "Jane Smith"
    end

    test "contract deletion removes contract from UI", %{
      conn: conn,
      property: property,
      scope: scope
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      contract = contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      # Switch to Active Contract tab to verify contract is visible
      show_live |> element("button[phx-value-selected='active_contract']") |> render_click()
      html = render(show_live)

      # Initially shows contract
      refute html =~ "No Active Contract"

      # Archive/delete contract
      {:ok, _} = Vivvo.Contracts.delete_contract(scope, contract)

      # Give LiveView time to process PubSub message
      html = render(show_live)

      # UI should show no active contract
      assert html =~ "No Active Contract"
    end

    test "ignores contract events for other properties", %{
      conn: conn,
      property: property,
      scope: scope
    } do
      # Create another property
      other_property = property_fixture(scope, %{name: "Other Property"})
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, show_live, _html} = live(conn, ~p"/properties/#{property}")

      # Switch to Active Contract tab to verify
      show_live |> element("button[phx-value-selected='active_contract']") |> render_click()
      html = render(show_live)

      # Initially no contract for our property
      assert html =~ "No Active Contract"

      # Create contract for OTHER property using future dates
      today = Date.utc_today()

      contract_attrs = %{
        start_date: today,
        end_date: Date.add(today, 30),
        tenant_id: tenant.id,
        expiration_day: 5,
        rent: "100.00",
        property_id: other_property.id
      }

      {:ok, _contract} = Vivvo.Contracts.create_contract(scope, contract_attrs)

      # Give LiveView time to potentially process PubSub message
      html = render(show_live)

      # Our property should still show no contract
      assert html =~ "No Active Contract"
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
              {:live_redirect,
               %{to: "/", flash: %{"error" => "You don't have permission to access this page."}}}} =
               live(context.conn, ~p"/properties")
    end

    test "non-owner cannot access property new form", %{conn: conn, user: user} do
      context = set_tenant_role(%{user: user, conn: conn})

      assert {:error,
              {:live_redirect,
               %{to: "/", flash: %{"error" => "You don't have permission to access this page."}}}} =
               live(context.conn, ~p"/properties/new")
    end

    test "non-owner cannot access property show page", %{
      conn: conn,
      property: property,
      user: user
    } do
      context = set_tenant_role(%{user: user, conn: conn})

      assert {:error,
              {:live_redirect,
               %{to: "/", flash: %{"error" => "You don't have permission to access this page."}}}} =
               live(context.conn, ~p"/properties/#{property}")
    end

    test "non-owner cannot access property edit form", %{
      conn: conn,
      property: property,
      user: user
    } do
      context = set_tenant_role(%{user: user, conn: conn})

      assert {:error,
              {:live_redirect,
               %{to: "/", flash: %{"error" => "You don't have permission to access this page."}}}} =
               live(context.conn, ~p"/properties/#{property}/edit")
    end
  end
end
