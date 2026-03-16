defmodule VivvoWeb.HomeLiveTest do
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

  defp ensure_tenant_role(%{user: user, conn: conn} = context) do
    {:ok, updated_user} = Accounts.update_user_current_role(user, %{current_role: :tenant})
    updated_scope = Scope.for_user(updated_user)
    conn = log_in_user(conn, updated_user)
    Map.merge(context, %{user: updated_user, scope: updated_scope, conn: conn})
  end

  describe "owner dashboard" do
    setup :ensure_owner_role

    test "renders home page for owner with expired contract having pending payment", %{
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

      # Visit the home page as the owner -- should NOT crash
      {:ok, _view, html} = live(conn, ~p"/")

      # Verify basic owner dashboard elements render
      assert html =~ "Dashboard"
    end

    test "renders home page for owner with active contract", %{conn: conn, scope: scope} do
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

      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Dashboard"
    end
  end

  describe "tenant dashboard" do
    setup :ensure_tenant_role

    test "renders home page for tenant with expired contract", %{
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

      # Visit the home page as the tenant -- should NOT crash
      {:ok, _view, html} = live(conn, ~p"/")

      # Verify basic tenant dashboard elements render
      assert html =~ "Contract Details"
    end

    test "renders home page for tenant with active contract", %{
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

      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Contract Details"
    end
  end
end
