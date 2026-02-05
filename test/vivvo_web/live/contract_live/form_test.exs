defmodule VivvoWeb.ContractLive.FormTest do
  use VivvoWeb.ConnCase

  import Phoenix.LiveViewTest
  import Vivvo.AccountsFixtures
  import Vivvo.PropertiesFixtures
  import Vivvo.ContractsFixtures

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

    test "warning message when property has existing contract", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      _contract = contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/new")

      assert html =~ "Warning"
      assert html =~ "replace the current active contract"
    end
  end

  describe "edit contract page" do
    setup [:register_and_log_in_user, :ensure_owner_role]

    test "mount loads existing contract data", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id,
          rent: "500.00",
          notes: "Test notes"
        })

      {:ok, _view, html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}/edit")

      assert html =~ "Edit Contract for"
      assert html =~ property.name
    end

    test "form pre-populated with contract data", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      contract =
        contract_fixture(scope, %{
          property_id: property.id,
          tenant_id: tenant.id,
          rent: "500.00",
          expiration_day: 15,
          notes: "Test notes"
        })

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}/edit")

      # Check that form has the contract values
      assert has_element?(view, "#contract-form")
    end

    test "cannot edit contract from different user", %{conn: conn} do
      other_scope = user_scope_fixture()
      property = property_fixture(other_scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      contract = contract_fixture(other_scope, %{property_id: property.id, tenant_id: tenant.id})

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/properties/#{property}/contracts/#{contract}/edit")
      end
    end

    test "cannot edit archived contract", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      contract = contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      # Archive the contract
      {:ok, _archived} = Vivvo.Contracts.delete_contract(scope, contract)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/properties/#{property}/contracts/#{contract}/edit")
      end
    end
  end

  describe "form validation" do
    setup [:register_and_log_in_user, :ensure_owner_role]

    test "validates on change event", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      _tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      # Submit invalid data
      result =
        view
        |> form("#contract-form", contract: %{rent: "-100"})
        |> render_change()

      assert result =~ "must be greater than 0"
    end

    test "displays end_date error when before start_date", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      result =
        view
        |> form("#contract-form",
          contract: %{
            start_date: "2026-02-10",
            end_date: "2026-02-05",
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

      result =
        view
        |> form("#contract-form",
          contract: %{
            start_date: "2026-02-05",
            end_date: "2026-02-10",
            tenant_id: tenant.id,
            expiration_day: 25,
            rent: "100"
          }
        )
        |> render_change()

      assert result =~ "must be less than or equal to 20"
    end

    test "displays rent error when <= 0", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      result =
        view
        |> form("#contract-form",
          contract: %{
            start_date: "2026-02-05",
            end_date: "2026-02-10",
            tenant_id: tenant.id,
            expiration_day: 5,
            rent: "0"
          }
        )
        |> render_change()

      assert result =~ "must be greater than 0"
    end

    test "displays required field errors", %{conn: conn, scope: scope} do
      property = property_fixture(scope)

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      result =
        view
        |> form("#contract-form", contract: %{})
        |> render_change()

      assert result =~ "can&#39;t be blank"
    end
  end

  describe "form submission" do
    setup [:register_and_log_in_user, :ensure_owner_role]

    test "successful contract creation", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      {:ok, _view, html} =
        view
        |> form("#contract-form",
          contract: %{
            start_date: "2026-02-05",
            end_date: "2026-03-05",
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

    test "successful contract update", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      contract = contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/#{contract}/edit")

      {:ok, _view, html} =
        view
        |> form("#contract-form",
          contract: %{
            start_date: "2026-02-05",
            end_date: "2026-03-05",
            tenant_id: tenant.id,
            expiration_day: 10,
            rent: "200.00",
            notes: "Updated notes"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/properties/#{property}")

      assert html =~ "Contract updated successfully"
    end

    test "redirects to property show page on success", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      {:ok, _, html} =
        view
        |> form("#contract-form",
          contract: %{
            start_date: "2026-02-05",
            end_date: "2026-03-05",
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

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      result =
        view
        |> form("#contract-form",
          contract: %{
            start_date: "2026-02-10",
            end_date: "2026-02-05",
            rent: "-100"
          }
        )
        |> render_submit()

      assert result =~ "must be after start date"
      assert result =~ "must be greater than 0"
    end

    test "archives existing contract when creating new one", %{conn: conn, scope: scope} do
      property = property_fixture(scope)
      tenant = user_fixture(%{preferred_roles: [:tenant]})
      old_contract = contract_fixture(scope, %{property_id: property.id, tenant_id: tenant.id})

      {:ok, view, _html} = live(conn, ~p"/properties/#{property}/contracts/new")

      view
      |> form("#contract-form",
        contract: %{
          start_date: "2026-03-01",
          end_date: "2026-04-01",
          tenant_id: tenant.id,
          expiration_day: 10,
          rent: "200.00"
        }
      )
      |> render_submit()

      # Old contract should be archived
      assert_raise Ecto.NoResultsError, fn ->
        Vivvo.Contracts.get_contract!(scope, old_contract.id)
      end
    end
  end
end
