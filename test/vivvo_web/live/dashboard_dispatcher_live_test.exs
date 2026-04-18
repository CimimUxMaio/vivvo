defmodule VivvoWeb.DashboardDispatcherLiveTest do
  use VivvoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Vivvo.AccountsFixtures

  describe "role-based redirection" do
    test "redirects tenant to /tenant/dashboard", %{conn: conn} do
      user = user_fixture(%{preferred_roles: [:tenant], current_role: :tenant})
      conn = log_in_user(conn, user)

      {:error, {:live_redirect, %{to: "/tenant/dashboard"}}} = live(conn, ~p"/")
    end

    test "redirects owner to /owner/dashboard", %{conn: conn} do
      user = user_fixture(%{preferred_roles: [:owner], current_role: :owner})
      conn = log_in_user(conn, user)

      {:error, {:live_redirect, %{to: "/owner/dashboard"}}} = live(conn, ~p"/")
    end
  end
end
