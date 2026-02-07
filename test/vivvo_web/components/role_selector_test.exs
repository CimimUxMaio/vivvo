defmodule VivvoWeb.Components.RoleSelectorTest do
  use VivvoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Vivvo.AccountsFixtures

  alias Vivvo.Accounts

  describe "RoleSelector component" do
    test "not rendered when user has single preferred role", %{conn: conn} do
      user =
        user_fixture(%{preferred_roles: [:owner], current_role: :owner})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      refute has_element?(lv, "#role-selector")
    end

    test "visible when user has multiple preferred roles", %{conn: conn} do
      user =
        user_fixture(%{preferred_roles: [:owner, :tenant], current_role: :owner})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      assert has_element?(lv, "#role-selector")
      assert has_element?(lv, "#role-selector button")
    end

    test "displays capitalized labels for roles", %{conn: conn} do
      user =
        user_fixture(%{preferred_roles: [:owner, :tenant], current_role: :owner})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      html = lv |> element("#role-selector") |> render()
      assert html =~ "Owner"
      assert html =~ "Tenant"
    end

    test "displays current role as active button", %{conn: conn} do
      user =
        user_fixture(%{preferred_roles: [:owner, :tenant], current_role: :tenant})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      assert has_element?(lv, "#role-selector")
      # The tenant button should have the active text color and the slider should be present
      tenant_button = lv |> element("#role-selector button", "Tenant") |> render()
      assert tenant_button =~ "text-primary"
      # Verify the sliding indicator exists
      assert has_element?(lv, "#role-selector div[class*='absolute'][class*='bg-base-100']")
    end

    test "switches role and navigates to home", %{conn: conn} do
      user =
        user_fixture(%{preferred_roles: [:owner, :tenant], current_role: :owner})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      # Verify Owner is initially active
      assert has_element?(lv, "#role-selector button[class*='text-primary']", "Owner")

      # Trigger role change by clicking the Tenant button
      lv
      |> element("#role-selector button", "Tenant")
      |> render_click()

      # Verify navigation to home after role change
      assert_redirect(lv, ~p"/")
    end

    test "updates role in database when switching", %{conn: conn} do
      user =
        user_fixture(%{preferred_roles: [:owner, :tenant], current_role: :owner})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      # Trigger role change by clicking the Tenant button
      lv
      |> element("#role-selector button", "Tenant")
      |> render_click()

      # Verify database update
      updated_user = Accounts.get_user!(user.id)
      assert updated_user.current_role == :tenant
    end
  end

  describe "HomeLive with current role display" do
    test "displays owner dashboard for authenticated owner user", %{conn: conn} do
      user =
        user_fixture(%{preferred_roles: [:owner, :tenant], current_role: :owner})

      {:ok, _lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      # User with owner role should see the owner dashboard
      assert html =~ "Dashboard"
    end

    test "redirects unauthenticated user to login", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end
end
