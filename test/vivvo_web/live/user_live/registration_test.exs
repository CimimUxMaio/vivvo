defmodule VivvoWeb.UserLive.RegistrationTest do
  use VivvoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Vivvo.AccountsFixtures

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Create your account"
      assert html =~ "Sign in"
      assert html =~ "First Name"
      assert html =~ "Last Name"
      assert html =~ "Phone Number"

      # MultiSelect LiveComponent content renders in the connected view
      connected_html = render(lv)
      assert connected_html =~ "Property Owner"
      assert connected_html =~ "Tenant"
    end

    test "multi-select: clicking add button opens dropdown and selecting option renders pill",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      # Initially the dropdown button should show "Add"
      assert render(lv) =~ "Add"

      # Initially no pills should be rendered (placeholder visible)
      html = render(lv)
      assert html =~ "Select your role(s)..."

      # Should not have a selected pill (no span with cursor-pointer class and remove-option handler)
      refute html =~ ~r/cursor-pointer[^>]*phx-click="remove-option"[^>]*>[^<]*Property Owner/

      # Click the toggle-dropdown button to open the dropdown
      lv
      |> element("#role-selector button[phx-click='toggle-dropdown']")
      |> render_click()

      # The dropdown should now be visible with options
      html = render(lv)
      assert html =~ "Property Owner"
      assert html =~ "Tenant"

      # Click on the "Property Owner" option to select it
      lv
      |> element("#role-selector button[phx-click='add-option'][phx-value-selected='owner']")
      |> render_click()

      # Now the "Property Owner" pill should be rendered
      html = render(lv)
      assert html =~ "Property Owner"
      # The pill should be clickable for removal
      assert html =~ "phx-click=\"remove-option\""
      assert html =~ "phx-value-selected=\"owner\""

      # The dropdown should be closed (hidden class applied)
      assert html =~ "hidden"
    end

    test "multi-select: selecting multiple options renders all pills", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      # Select first role - Property Owner
      lv
      |> element("#role-selector button[phx-click='toggle-dropdown']")
      |> render_click()

      lv
      |> element("#role-selector button[phx-click='add-option'][phx-value-selected='owner']")
      |> render_click()

      # Select second role - Tenant
      lv
      |> element("#role-selector button[phx-click='toggle-dropdown']")
      |> render_click()

      lv
      |> element("#role-selector button[phx-click='add-option'][phx-value-selected='tenant']")
      |> render_click()

      # Both pills should be rendered
      html = render(lv)
      assert html =~ "Property Owner"
      assert html =~ "Tenant"
    end

    test "multi-select: clicking remove button removes the pill", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      # First select a role
      lv
      |> element("#role-selector button[phx-click='toggle-dropdown']")
      |> render_click()

      lv
      |> element("#role-selector button[phx-click='add-option'][phx-value-selected='owner']")
      |> render_click()

      # Verify it's selected
      html = render(lv)
      assert html =~ "Property Owner"

      # Click on the pill to remove it
      lv
      |> element("#role-selector button[phx-click='remove-option'][phx-value-selected='owner']")
      |> render_click()

      # The pill should be gone and placeholder should be back
      html = render(lv)

      # Should not have a selected pill (no span with cursor-pointer class and remove-option handler)
      refute html =~ ~r/cursor-pointer[^>]*phx-click="remove-option"[^>]*>[^<]*Property Owner/
      assert html =~ "Select your role(s)..."
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces"})

      assert result =~ "Create your account"
      assert result =~ "must have the @ sign and no spaces"
    end
  end

  describe "register user" do
    test "creates account but does not log in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      # Don't include current_role in form - it's auto-calculated
      attrs =
        valid_user_attributes(email: email)
        |> Map.delete(:current_role)

      # Submit form directly without form helper validation
      {:ok, _lv, html} =
        lv
        |> element("#registration_form")
        |> render_submit(%{user: attrs})
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~
               ~r/An email was sent to .*, please access it to confirm your account/
    end

    test "creates account with all required fields", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      # Submit form with all required fields including preferred_roles
      attrs =
        valid_user_attributes(
          email: email,
          first_name: "John",
          last_name: "Doe",
          phone_number: "+1234567890",
          preferred_roles: ["owner"]
        )
        |> Map.delete(:current_role)

      # Submit form directly without form helper validation
      element(lv, "#registration_form")
      |> render_submit(%{user: attrs})

      user = Vivvo.Accounts.get_user_by_email(email)
      assert user
      assert user.first_name == "John"
      assert user.last_name == "Doe"
      assert user.phone_number == "+1234567890"
      assert user.preferred_roles == [:owner]
      assert user.current_role == :owner
    end

    test "current role is automatically set to first preferred role", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      # Submit form with multiple roles - first one becomes current_role
      attrs =
        valid_user_attributes(
          email: email,
          preferred_roles: ["tenant", "owner"]
        )
        |> Map.delete(:current_role)

      # Submit form directly without form helper validation
      element(lv, "#registration_form")
      |> render_submit(%{user: attrs})

      user = Vivvo.Accounts.get_user_by_email(email)
      assert user.preferred_roles == [:tenant, :owner]
      # First role in the list becomes current_role
      assert user.current_role == :tenant
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      user = user_fixture(%{email: "test@email.com"})

      # Don't include current_role in form - it's auto-calculated
      attrs = valid_user_attributes(email: user.email) |> Map.delete(:current_role)

      # Submit form directly without form helper validation
      result =
        lv
        |> element("#registration_form")
        |> render_submit(%{user: attrs})

      assert result =~ "has already been taken"
    end

    test "renders error when first name is missing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: valid_user_attributes(%{first_name: ""}))

      assert result =~ "can&#39;t be blank"
    end

    test "renders error when last name is missing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: valid_user_attributes(%{last_name: ""}))

      assert result =~ "can&#39;t be blank"
    end

    test "renders error when phone number is missing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: valid_user_attributes(%{phone_number: ""}))

      assert result =~ "can&#39;t be blank"
    end

    test "renders error when phone number is invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: valid_user_attributes(%{phone_number: "abc"}))

      assert result =~ "must be a valid phone number"
    end

    test "renders error when phone number is too short", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: valid_user_attributes(%{phone_number: "123"}))

      assert result =~ "should be at least 10 character(s)"
    end

    test "renders error when phone number is too long", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: valid_user_attributes(%{phone_number: "123456789012345678901"}))

      assert result =~ "should be at most 20 character(s)"
    end

    test "renders error when no preferred roles are selected", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      # Submit form without preferred_roles to trigger validation error
      # Note: The error may not be visible in the HTML due to used_input? behavior,
      # but the form should not submit successfully
      result =
        lv
        |> element("#registration_form")
        |> render_submit(%{
          "user" => %{
            "email" => email,
            "first_name" => "Test",
            "last_name" => "User",
            "phone_number" => "+1234567890",
            "preferred_roles" => []
          }
        })

      # User should not be created
      assert Vivvo.Accounts.get_user_by_email(email) == nil

      # We should still be on the registration page (not redirected)
      assert result =~ "Create your account"
    end

    test "renders error when first name is too long", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      long_name = String.duplicate("a", 101)

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: valid_user_attributes(%{first_name: long_name}))

      assert result =~ "should be at most 100 character(s)"
    end

    test "renders error when last name is too long", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      long_name = String.duplicate("a", 101)

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: valid_user_attributes(%{last_name: long_name}))

      assert result =~ "should be at most 100 character(s)"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Sign in link is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Sign in")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert login_html =~ "Welcome back"
    end
  end
end
