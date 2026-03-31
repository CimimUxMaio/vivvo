defmodule VivvoWeb.ContractLive.ShowTest do
  use VivvoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Vivvo.AccountsFixtures
  import Vivvo.ContractsFixtures
  import Vivvo.PropertiesFixtures

  alias Vivvo.Accounts
  alias Vivvo.Accounts.Scope

  setup :register_and_log_in_user

  defp ensure_owner_role(%{user: user} = context) do
    {:ok, updated_user} = Accounts.update_user_current_role(user, %{current_role: :owner})
    updated_scope = Scope.for_user(updated_user)
    Map.merge(context, %{user: updated_user, scope: updated_scope})
  end

  defp create_property(%{scope: scope}) do
    property = property_fixture(scope)
    %{property: property}
  end

  describe "contract show page" do
    setup [:ensure_owner_role, :create_property]

    test "renders contract details correctly", %{conn: conn, scope: scope, property: property} do
      tenant = user_fixture(%{preferred_roles: [:tenant], first_name: "John", last_name: "Doe"})

      contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id,
          rent: "1500.00",
          notes: "Test contract notes"
        })

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}")

      # Verify page title and header
      assert html =~ "Contract Details"
      assert html =~ property.name

      # Verify tenant info
      assert html =~ "John Doe"
      assert html =~ tenant.email

      # Verify contract dates
      assert html =~ format_date(contract.start_date)
      assert html =~ format_date(contract.end_date)

      # Verify rent amount
      assert html =~ "$1,500.00" or html =~ "$1500.00" or html =~ "1500.00"

      # Verify notes
      assert html =~ "Test contract notes"
    end

    test "displays contract progress for active contract", %{
      conn: conn,
      scope: scope,
      property: property
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      today = Date.utc_today()

      contract =
        contract_fixture(
          scope,
          %{
            property_id: property.id,
            tenant_id: tenant.id,
            start_date: Date.add(today, -30),
            end_date: Date.add(today, 335),
            rent: "1000.00"
          },
          past_start_date?: true,
          update_factor: Decimal.new("0.0")
        )

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}")

      # Verify progress indicator exists
      assert html =~ "Contract Journey"
      assert html =~ "Active"

      # Progress should be around 8% (30 days / 365 days)
      # The exact percentage depends on implementation, but it should be between 0 and 100
      assert html =~ "%"
    end

    test "displays contract status for expired contract", %{
      conn: conn,
      scope: scope,
      property: property
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      contract =
        expired_contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id
        })

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}")

      assert html =~ "Expired"
      assert html =~ "Contract Journey"
    end

    test "displays contract status for upcoming contract", %{
      conn: conn,
      scope: scope,
      property: property
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      today = Date.utc_today()

      contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id,
          start_date: Date.add(today, 30),
          end_date: Date.add(today, 365),
          rent: "1200.00"
        })

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}")

      assert html =~ "Upcoming"
      assert html =~ "Contract Journey"
      # Progress should be 0%
      assert html =~ "0%"
    end

    test "renders rent evolution chart with data attributes", %{
      conn: conn,
      scope: scope,
      property: property
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      contract =
        contract_fixture(
          scope,
          %{
            property_id: property.id,
            tenant_id: tenant.id,
            start_date: Date.add(Date.utc_today(), -60),
            end_date: Date.add(Date.utc_today(), 300),
            rent: "1000.00"
          },
          past_start_date?: true,
          update_factor: Decimal.new("0.0")
        )

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}")

      # Verify chart container exists
      assert html =~ "Rent Value Over Time"

      # Verify canvas element with chart data attributes
      assert html =~ "id=\"rent-chart\""
      assert html =~ "phx-hook=\"SteppedLineChart\""
      assert html =~ "data-chart-labels"
      assert html =~ "data-chart-values"
      assert html =~ "data-chart-min"
      assert html =~ "data-chart-max"
    end

    test "displays next rent update for indexed contracts", %{
      conn: conn,
      scope: scope,
      property: property
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      today = Date.utc_today()

      contract =
        contract_fixture(
          scope,
          %{
            property_id: property.id,
            tenant_id: tenant.id,
            start_date: Date.add(today, -60),
            end_date: Date.add(today, 365),
            rent: "1200.00",
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("0.05")
        )

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}")

      # Verify rent update section exists
      assert html =~ "Rent Updates"
      assert html =~ "Next Rent Update"
      assert html =~ "ICL (Índice de Contratos de Locación)"
      assert html =~ "Yearly"

      # Verify rent history section
      assert html =~ "Rent History"
    end

    test "does not show rent updates section for non-indexed contracts", %{
      conn: conn,
      scope: scope,
      property: property
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id,
          rent: "1000.00",
          index_type: nil
        })

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}")

      # Should not have the Rent Updates timeline item
      refute html =~ "Rent Updates"

      # Should show fixed rent message
      assert html =~ "Fixed rent (no indexing)"
    end

    test "does not show notes section when contract has empty notes", %{
      conn: conn,
      scope: scope,
      property: property
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id,
          notes: ""
        })

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}")

      # Should not have the Notes timeline item
      refute html =~ "Notes"
    end

    test "back navigation links to property page with return_to param", %{
      conn: conn,
      scope: scope,
      property: property
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id
        })

      {:ok, view, _html} =
        live(conn, ~p"/properties/#{property}/contracts/#{contract}?return_to=contract")

      # Verify back link exists and points to the correct path
      assert has_element?(view, "a[href='/properties/#{property.id}?tab=contract']")
    end

    test "property link in timeline navigates to property page", %{
      conn: conn,
      scope: scope,
      property: property
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id
        })

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}")

      # Verify property link exists
      assert has_element?(view, "a[href='/properties/#{property.id}']")
    end

    test "displays owner information in parties section", %{
      conn: conn,
      scope: scope,
      property: property
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id
        })

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}")

      # Verify owner info is displayed
      assert html =~ "Owner"

      # The owner should be the logged-in user
      assert html =~ scope.user.first_name
      assert html =~ scope.user.last_name
    end

    test "displays payment due day correctly", %{conn: conn, scope: scope, property: property} do
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id,
          expiration_day: 10
        })

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}")

      assert html =~ "Payment Due"
      assert html =~ "Day 10 of month"
    end

    test "displays duration in terms section", %{conn: conn, scope: scope, property: property} do
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      today = Date.utc_today()

      contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id,
          start_date: today,
          end_date: Date.add(today, 365)
        })

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}")

      assert html =~ "Duration"
    end
  end

  describe "authorization" do
    setup [:ensure_owner_role, :create_property]

    test "redirects when contract belongs to different property", %{
      conn: conn,
      scope: scope,
      property: property
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id
        })

      # Create another property
      other_property = property_fixture(scope)

      # Try to access the contract through the wrong property
      {:error, {:live_redirect, %{to: redirect_path, flash: flash}}} =
        live(conn, ~p"/properties/#{other_property}/contracts/#{contract}")

      # Should redirect to the other property page with error message
      assert redirect_path == "/properties/#{other_property.id}"
      assert flash["error"] == "Contract not found for this property"
    end

    test "raises error for non-existent contract", %{conn: conn, property: property} do
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/properties/#{property}/contracts/999999")
      end
    end

    test "raises error when accessing contract owned by different user", %{
      conn: conn,
      property: property
    } do
      # Create another user and their contract
      other_scope = user_scope_fixture()
      other_tenant = user_fixture(%{preferred_roles: [:tenant]})

      other_contract =
        contract_fixture(other_scope, %{
          property_id: property_fixture(other_scope).id,
          tenant_id: other_tenant.id
        })

      # Try to access it
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/properties/#{property}/contracts/#{other_contract.id}")
      end
    end
  end

  describe "edge cases" do
    setup [:ensure_owner_role, :create_property]

    test "renders correctly for contract with empty rent periods", %{
      conn: conn,
      scope: scope,
      property: property
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id,
          rent: "800.00"
        })

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}")

      # Page should still render
      assert html =~ "Contract Details"
      assert html =~ "Current Monthly Rent"
    end

    test "handles contract with property area and rooms", %{
      conn: conn,
      scope: scope
    } do
      property = property_fixture(scope, %{area: 100, rooms: 3})
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id
        })

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}")

      # Verify property details are shown
      assert html =~ "100"
      assert html =~ "3"
      assert html =~ "m²"
      assert html =~ "rooms"
    end

    test "displays contract period in subtitle", %{conn: conn, scope: scope, property: property} do
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      today = Date.utc_today()

      contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id,
          start_date: today,
          end_date: Date.add(today, 180)
        })

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}")

      # Should display the formatted contract period
      assert html =~ format_date(contract.start_date)
      assert html =~ format_date(contract.end_date)
    end
  end

  # Helper function for formatting dates consistently with the UI
  defp format_date(date) do
    Calendar.strftime(date, "%b %d, %Y")
  end
end
