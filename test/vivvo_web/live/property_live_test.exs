defmodule VivvoWeb.PropertyLiveTest do
  use VivvoWeb.ConnCase

  import Phoenix.LiveViewTest
  import Vivvo.PropertiesFixtures

  @create_attrs %{name: "some name", address: "some address", area: 42, rooms: 42, notes: "some notes"}
  @update_attrs %{name: "some updated name", address: "some updated address", area: 43, rooms: 43, notes: "some updated notes"}
  @invalid_attrs %{name: nil, address: nil, area: nil, rooms: nil, notes: nil}

  setup :register_and_log_in_user

  defp create_property(%{scope: scope}) do
    property = property_fixture(scope)

    %{property: property}
  end

  describe "Index" do
    setup [:create_property]

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
  end

  describe "Show" do
    setup [:create_property]

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
end
