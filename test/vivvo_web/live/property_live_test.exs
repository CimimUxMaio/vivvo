defmodule VivvoWeb.PropertyLiveTest do
  use VivvoWeb.ConnCase

  import Phoenix.LiveViewTest
  import Vivvo.PropertiesFixtures

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
