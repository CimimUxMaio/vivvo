defmodule VivvoWeb.TenantDashboardLiveTest do
  use VivvoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Vivvo.AccountsFixtures
  import Vivvo.ContractsFixtures
  import Vivvo.PropertiesFixtures

  alias Vivvo.Accounts
  alias Vivvo.Accounts.Scope

  setup :register_and_log_in_user

  defp ensure_tenant_role(%{user: user, conn: conn} = context) do
    {:ok, updated_user} = Accounts.update_user_current_role(user, %{current_role: :tenant})
    updated_scope = Scope.for_user(updated_user)
    conn = log_in_user(conn, updated_user)
    Map.merge(context, %{user: updated_user, scope: updated_scope, conn: conn})
  end

  describe "tenant dashboard" do
    setup :ensure_tenant_role

    test "renders dashboard for tenant with expired contract", %{
      conn: conn,
      user: tenant,
      scope: _tenant_scope
    } do
      # Create an owner to own the contract
      owner = user_fixture(%{preferred_roles: [:owner]})
      owner_scope = Scope.for_user(owner)
      property = property_fixture(owner_scope)

      # Create an expired non-archived contract assigned to this tenant
      _expired_contract =
        expired_contract_fixture(owner_scope, %{
          tenant_id: tenant.id,
          property_id: property.id,
          rent: "800.00"
        })

      # Visit the dashboard as the tenant -- should NOT crash
      {:ok, _view, html} = live(conn, ~p"/tenant/dashboard")

      # Verify basic tenant dashboard elements render
      assert html =~ "Contract Details"
    end

    test "renders dashboard for tenant with active contract", %{
      conn: conn,
      user: tenant,
      scope: _tenant_scope
    } do
      # Baseline sanity check
      owner = user_fixture(%{preferred_roles: [:owner]})
      owner_scope = Scope.for_user(owner)
      property = property_fixture(owner_scope)

      _contract =
        contract_fixture(
          owner_scope,
          %{
            tenant_id: tenant.id,
            property_id: property.id,
            start_date: Date.add(Date.utc_today(), -30),
            end_date: Date.add(Date.utc_today(), 365),
            rent: "900.00",
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("0.0")
        )

      {:ok, _view, html} = live(conn, ~p"/tenant/dashboard")
      assert html =~ "Contract Details"
    end
  end

  describe "role verification" do
    test "redirects owner to home when accessing tenant dashboard", %{
      conn: conn,
      user: _user
    } do
      # User is already an owner by default from register_and_log_in_user
      # Try to access tenant dashboard as owner - should redirect immediately
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/tenant/dashboard")
    end
  end
end
