defmodule VivvoWeb.OwnerDashboardLiveTest do
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

  describe "owner dashboard" do
    setup :ensure_owner_role

    test "renders dashboard for owner with expired contract having pending payment", %{
      conn: conn,
      scope: scope
    } do
      # Create a tenant user
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      tenant_scope = Scope.for_user(tenant)

      # Create a property owned by the owner
      property = property_fixture(scope)

      # Create an expired contract (end_date in the past) owned by this owner, with this tenant
      expired_contract =
        expired_contract_fixture(scope, %{
          tenant_id: tenant.id,
          property_id: property.id,
          rent: "1000.00"
        })

      # Create a pending payment on the expired contract (as the tenant)
      {:ok, _payment} =
        Vivvo.Payments.create_payment(tenant_scope, %{
          contract_id: expired_contract.id,
          amount: "1000.00",
          payment_number: 1
        })

      # Visit the dashboard as the owner -- should NOT crash
      {:ok, _view, html} = live(conn, ~p"/owner/dashboard")

      # Verify basic owner dashboard elements render
      assert html =~ "Dashboard"
    end

    test "renders dashboard for owner with active contract", %{conn: conn, scope: scope} do
      # Baseline sanity check -- active contract should always work
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      tenant_scope = Scope.for_user(tenant)
      property = property_fixture(scope)

      contract =
        contract_fixture(
          scope,
          %{
            tenant_id: tenant.id,
            property_id: property.id,
            start_date: Date.add(Date.utc_today(), -30),
            end_date: Date.add(Date.utc_today(), 365),
            rent: "1200.00",
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("0.0")
        )

      {:ok, _payment} =
        Vivvo.Payments.create_payment(tenant_scope, %{
          contract_id: contract.id,
          amount: "1200.00",
          payment_number: 1
        })

      {:ok, _view, html} = live(conn, ~p"/owner/dashboard")
      assert html =~ "Dashboard"
    end

    test "pending_payment_row uses date context for current_rent_value", %{
      conn: conn,
      scope: scope
    } do
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      tenant_scope = Scope.for_user(tenant)
      property = property_fixture(scope)
      today = Date.utc_today()

      # Create a contract
      contract =
        contract_fixture(
          scope,
          %{
            tenant_id: tenant.id,
            property_id: property.id,
            start_date: Date.add(today, -30),
            end_date: Date.add(today, 365),
            rent: "1000.00",
            expiration_day: 1
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
        )

      # Create a pending payment
      {:ok, payment} =
        Vivvo.Payments.create_payment(tenant_scope, %{
          contract_id: contract.id,
          amount: "1000.00",
          payment_number: 1,
          status: :pending
        })

      {:ok, view, _html} = live(conn, ~p"/owner/dashboard")

      # Verify the pending payment row renders without error
      # This tests that pending_payment_row properly calculates due_date
      # and passes it to current_rent_value
      assert has_element?(view, "#payment-#{payment.id}")
    end

    test "redirects tenant to home when accessing owner dashboard", %{
      conn: conn,
      user: user
    } do
      # Switch user to tenant role
      {:ok, tenant_user} = Accounts.update_user_current_role(user, %{current_role: :tenant})
      conn = log_in_user(conn, tenant_user)

      # Try to access owner dashboard as tenant - should redirect immediately
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/owner/dashboard")
    end
  end
end
