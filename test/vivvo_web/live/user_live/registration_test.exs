defmodule VivvoWeb.UserLive.RegistrationTest do
  use VivvoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Vivvo.AccountsFixtures

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Register"
      assert html =~ "Log in"
      assert html =~ "First Name"
      assert html =~ "Last Name"
      assert html =~ "Phone Number"
      assert html =~ "Property Owner"
      assert html =~ "Tenant"
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

      assert result =~ "Register"
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

      form = form(lv, "#registration_form", user: attrs)

      {:ok, _lv, html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~
               ~r/An email was sent to .*, please access it to confirm your account/
    end

    test "creates account with all required fields", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      # Don't include current_role in form - it's auto-calculated
      attrs =
        valid_user_attributes(
          email: email,
          first_name: "John",
          last_name: "Doe",
          phone_number: "+1234567890",
          preferred_roles: ["owner"]
        )
        |> Map.delete(:current_role)

      form = form(lv, "#registration_form", user: attrs)

      render_submit(form)

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

      # Don't include current_role in form - it's auto-calculated from preferred_roles
      attrs =
        valid_user_attributes(
          email: email,
          preferred_roles: ["tenant", "owner"]
        )
        |> Map.delete(:current_role)

      form = form(lv, "#registration_form", user: attrs)

      render_submit(form)

      user = Vivvo.Accounts.get_user_by_email(email)
      assert user.preferred_roles == [:tenant, :owner]
      assert user.current_role == :tenant
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      user = user_fixture(%{email: "test@email.com"})

      # Don't include current_role in form - it's auto-calculated
      attrs = valid_user_attributes(email: user.email) |> Map.delete(:current_role)

      result =
        lv
        |> form("#registration_form", user: attrs)
        |> render_submit()

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

      # Don't include current_role in form - it's auto-calculated
      attrs = valid_user_attributes(%{preferred_roles: []}) |> Map.delete(:current_role)

      result =
        lv
        |> form("#registration_form", user: attrs)
        |> render_submit()

      assert result =~ "must select at least one role"
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
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Log in")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert login_html =~ "Log in"
    end
  end
end
