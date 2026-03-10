defmodule VivvoWeb.ContractLive.FormTest do
  use VivvoWeb.ConnCase

  import Phoenix.LiveViewTest
  import Vivvo.AccountsFixtures
  import Vivvo.PropertiesFixtures

  alias Vivvo.Accounts
  alias Vivvo.Accounts.Scope

  defp ensure_owner_role(%{user: user} = context) do
    {:ok, updated_user} = Accounts.update_user_current_role(user, %{current_role: :owner})
    updated_scope = Scope.for_user(updated_user)
    Map.merge(context, %{user: updated_user, scope: updated_scope})
  end

  describe "new contract page" do
    setup [:register_and_log_in_user, :ensure_owner_role]

    test "mount with valid property_id loads form", %{conn: conn, scope: scope} do
      property = property_fixture(scope)

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/new")

      assert html =~ "New Contract for"
      assert html =~ property.name
    end

    test "mount with invalid property_id raises error", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/properties/999999/contracts/new")
      end
    end

    test "mount with property owned by different user raises error", %{conn: conn} do
      other_scope = user_scope_fixture()
      property = property_fixture(other_scope)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/properties/#{property}/contracts/new")
      end
    end

    test "form displays property name and address", %{conn: conn, scope: scope} do
      property = property_fixture(scope, %{name: "Test Property", address: "123 Main St"})

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/new")

      assert html =~ "Test Property"
      assert html =~ "123 Main St"
    end

    test "tenant dropdown populated with tenant users", %{conn: conn, scope: scope} do
      property = property_fixture(scope)

      _tenant =
        user_fixture(%{preferred_roles: [:tenant], last_name: "Smith", first_name: "John"})

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/new")

      assert html =~ "Smith, John"
    end

    test "tenant dropdown empty state message", %{conn: conn, scope: scope} do
      property = property_fixture(scope)

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/new")

      # Check if form is rendered
      assert html =~ "contract-form"
    end

    test "all form fields rendered", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      _tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/new")

      assert html =~ "contract-form"
      assert html =~ "Tenant"
      assert html =~ "Start Date"
      assert html =~ "End Date"
      assert html =~ "Payment Due Day"
      assert html =~ "Monthly Rent"
      assert html =~ "Notes"
    end

    test "index type field rendered", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      _tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/new")

      assert html =~ "Index Type"
    end

    test "rent period duration field rendered when index_type selected", %{
      conn: conn,
      scope: scope
    } do
      property = property_fixture(scope)
      _tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      # Initially not visible
      html = render(view)
      refute html =~ "Rent Update Period"

      # Select index type to show rent period duration
      result =
        view
        |> form("#contract-form", contract: %{index_type: "cpi"})
        |> render_change()

      assert result =~ "Rent Update Period"
    end
  end

  describe "form validation" do
    setup [:register_and_log_in_user, :ensure_owner_role]

    test "validates end date after start date on change event", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      # Use future dates for validation testing
      today = Date.utc_today()
      start_date = Date.add(today, 30)
      end_date = Date.add(today, 10)

      # Submit invalid data with end_date before start_date
      result =
        view
        |> form("#contract-form",
          contract: %{
            start_date: Date.to_iso8601(start_date),
            end_date: Date.to_iso8601(end_date),
            tenant_id: tenant.id
          }
        )
        |> render_change()

      assert result =~ "must be after start date"
    end

    test "displays end_date error when before start_date", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      # Use future dates for validation testing
      today = Date.utc_today()
      start_date = Date.add(today, 30)
      end_date = Date.add(today, 10)

      result =
        view
        |> form("#contract-form",
          contract: %{
            start_date: Date.to_iso8601(start_date),
            end_date: Date.to_iso8601(end_date),
            tenant_id: tenant.id,
            expiration_day: 5,
            rent: "100"
          }
        )
        |> render_change()

      assert result =~ "must be after start date"
    end

    test "displays expiration_day error when out of range", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      # Use future dates for testing
      today = Date.utc_today()
      start_date = Date.add(today, 10)
      end_date = Date.add(today, 30)

      result =
        view
        |> form("#contract-form",
          contract: %{
            start_date: Date.to_iso8601(start_date),
            end_date: Date.to_iso8601(end_date),
            tenant_id: tenant.id,
            expiration_day: 25,
            rent: "100"
          }
        )
        |> render_change()

      assert result =~ "must be less than or equal to 20"
    end

    test "displays required field errors on submit", %{conn: conn, scope: scope} do
      property = property_fixture(scope)

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      # Use future dates for testing
      today = Date.utc_today()
      start_date = Date.add(today, 10)
      end_date = Date.add(today, 30)

      # Submit with missing required fields to trigger validation
      result =
        view
        |> form("#contract-form",
          contract: %{
            start_date: Date.to_iso8601(start_date),
            end_date: Date.to_iso8601(end_date)
          }
        )
        |> render_submit()

      # Check that validation errors are displayed
      assert result =~ "can&#39;t be blank"
    end

    test "displays end_date validation error", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      # Use future dates for validation testing
      today = Date.utc_today()
      start_date = Date.add(today, 30)
      end_date = Date.add(today, 10)

      result =
        view
        |> form("#contract-form",
          contract: %{
            start_date: Date.to_iso8601(start_date),
            end_date: Date.to_iso8601(end_date),
            tenant_id: tenant.id,
            expiration_day: 5
          }
        )
        |> render_submit()

      assert result =~ "must be after start date"
    end

    test "validates rent_period_duration must be > 0 when present", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      # First select index_type to make rent_period_duration visible
      view
      |> form("#contract-form", contract: %{index_type: "cpi"})
      |> render_change()

      # Use future dates for testing
      today = Date.utc_today()
      start_date = Date.add(today, 10)
      end_date = Date.add(today, 365)

      result =
        view
        |> form("#contract-form",
          contract: %{
            start_date: Date.to_iso8601(start_date),
            end_date: Date.to_iso8601(end_date),
            tenant_id: tenant.id,
            expiration_day: 5,
            rent: "1000",
            index_type: "cpi",
            rent_period_duration: "0"
          }
        )
        |> render_change()

      assert result =~ "must be greater than 0"
    end
  end

  describe "form submission" do
    setup [:register_and_log_in_user, :ensure_owner_role]

    test "successful contract creation", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      # Use future dates to avoid past_start_date validation error
      today = Date.utc_today()
      start_date = Date.add(today, 5)
      end_date = Date.add(today, 30)

      {:ok, _view, html} =
        view
        |> form("#contract-form",
          contract: %{
            start_date: Date.to_iso8601(start_date),
            end_date: Date.to_iso8601(end_date),
            tenant_id: tenant.id,
            expiration_day: 5,
            rent: "100.00",
            notes: "Test contract"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/properties/#{property}")

      assert html =~ "Contract created successfully"
    end

    test "successful contract creation with rent index settings", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      # First select index_type to make rent_period_duration visible
      view
      |> form("#contract-form", contract: %{index_type: "cpi"})
      |> render_change()

      # Use future dates to avoid past_start_date validation error
      today = Date.utc_today()
      start_date = Date.add(today, 5)
      end_date = Date.add(today, 365)

      {:ok, _view, html} =
        view
        |> form("#contract-form",
          contract: %{
            start_date: Date.to_iso8601(start_date),
            end_date: Date.to_iso8601(end_date),
            tenant_id: tenant.id,
            expiration_day: 5,
            rent: "1200.00",
            rent_period_duration: "12",
            index_type: "cpi",
            notes: "Contract with CPI indexing"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/properties/#{property}")

      assert html =~ "Contract created successfully"
    end

    test "redirects to property show page on success", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      # Use future dates to avoid past_start_date validation error
      today = Date.utc_today()
      start_date = Date.add(today, 5)
      end_date = Date.add(today, 30)

      {:ok, _, html} =
        view
        |> form("#contract-form",
          contract: %{
            start_date: Date.to_iso8601(start_date),
            end_date: Date.to_iso8601(end_date),
            tenant_id: tenant.id,
            expiration_day: 5,
            rent: "100.00"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/properties/#{property}")

      assert html =~ "Contract created successfully"
    end

    test "displays errors on validation failure", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      # Use future dates for validation testing
      today = Date.utc_today()
      start_date = Date.add(today, 30)
      end_date = Date.add(today, 10)

      result =
        view
        |> form("#contract-form",
          contract: %{
            start_date: Date.to_iso8601(start_date),
            end_date: Date.to_iso8601(end_date),
            tenant_id: tenant.id,
            expiration_day: 5
          }
        )
        |> render_submit()

      assert result =~ "must be after start date"
    end
  end
end
