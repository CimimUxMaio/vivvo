defmodule Vivvo.PaymentsTest do
  use Vivvo.DataCase

  alias Vivvo.Payments

  describe "payments" do
    alias Vivvo.Payments.Payment

    import Vivvo.AccountsFixtures, only: [user_scope_fixture: 0]
    import Vivvo.ContractsFixtures, only: [contract_fixture: 2, contract_fixture: 3]
    import Vivvo.PaymentsFixtures

    @invalid_attrs %{status: nil, amount: nil, payment_number: nil, notes: nil, contract_id: nil}

    test "list_payments/1 returns all scoped payments" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      payment = payment_fixture(scope)
      other_payment = payment_fixture(other_scope)
      assert Enum.map(Payments.list_payments(scope), & &1.id) == [payment.id]
      assert Enum.map(Payments.list_payments(other_scope), & &1.id) == [other_payment.id]
    end

    test "get_payment!/2 returns the payment with given id" do
      scope = user_scope_fixture()
      payment = payment_fixture(scope)
      other_scope = user_scope_fixture()
      assert Payments.get_payment!(scope, payment.id).id == payment.id
      assert_raise Ecto.NoResultsError, fn -> Payments.get_payment!(other_scope, payment.id) end
    end

    test "create_payment/2 with valid data creates a payment" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope, %{tenant_id: scope.user.id})

      valid_attrs = %{
        status: :pending,
        amount: "120.5",
        payment_number: 42,
        notes: "some notes",
        contract_id: contract.id
      }

      assert {:ok, %Payment{} = payment} = Payments.create_payment(scope, valid_attrs)
      assert payment.status == :pending
      assert payment.amount == Decimal.new("120.5")
      assert payment.payment_number == 42
      assert payment.notes == "some notes"
      assert payment.user_id == scope.user.id
      assert payment.contract_id == contract.id
    end

    test "create_payment/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Payments.create_payment(scope, @invalid_attrs)
    end

    test "create_payment/2 returns error when contract needs update" do
      scope = user_scope_fixture()

      # Create a contract with indexing that needs an update today.
      # We set the fixture's `today` to the last day of the previous month,
      # so periods are generated up to that date, creating a gap for today.
      today = Date.utc_today()

      last_month_end =
        today
        |> Date.shift(month: -1)
        |> Date.end_of_month()

      # Create contract starting 6 months before last_month_end with 3-month rent periods
      contract_start = Date.shift(today, month: -6)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(today, month: 6),
            rent: "1000.00",
            tenant_id: scope.user.id,
            index_type: :icl,
            rent_period_duration: 3
          },
          past_start_date?: true,
          update_factor: Decimal.new("0.0"),
          today: last_month_end
        )

      # Verify the contract needs update today (there's a gap period)
      assert Vivvo.Contracts.needs_update?(contract, today)

      # Attempting to create a payment should fail
      attrs = %{
        status: :pending,
        amount: "500.00",
        payment_number: 1,
        contract_id: contract.id
      }

      assert {:error, :contract_needs_update} = Payments.create_payment(scope, attrs)
    end

    test "create_payment/2 returns changeset error when contract belongs to another tenant" do
      # Create two different tenant scopes
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()

      # Create a contract that belongs to the OTHER tenant
      other_contract = contract_fixture(other_scope, %{tenant_id: other_scope.user.id})

      # Attempt to create a payment for the other tenant's contract
      attrs = %{
        status: :pending,
        amount: "500.00",
        payment_number: 1,
        contract_id: other_contract.id
      }

      # Unauthorized contract_id is stripped, so it returns same error as missing contract_id
      assert {:error, %Ecto.Changeset{}} = Payments.create_payment(scope, attrs)
    end

    test "update_payment/3 with valid data updates the payment" do
      scope = user_scope_fixture()
      payment = payment_fixture(scope)

      update_attrs = %{
        amount: "456.7",
        payment_number: 43,
        notes: "some updated notes"
      }

      assert {:ok, %Payment{} = payment} = Payments.update_payment(scope, payment, update_attrs)
      # Status remains pending (the default)
      assert payment.status == :pending
      assert payment.amount == Decimal.new("456.7")
      assert payment.payment_number == 43
      assert payment.notes == "some updated notes"
    end

    test "update_payment/3 with invalid scope returns unauthorized error" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      payment = payment_fixture(scope)

      assert {:error, :unauthorized} = Payments.update_payment(other_scope, payment, %{})
    end

    test "update_payment/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      payment = payment_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Payments.update_payment(scope, payment, @invalid_attrs)
      assert payment.id == Payments.get_payment!(scope, payment.id).id
    end

    test "delete_payment/2 deletes the payment" do
      scope = user_scope_fixture()
      payment = payment_fixture(scope)
      assert {:ok, %Payment{}} = Payments.delete_payment(scope, payment)
      assert_raise Ecto.NoResultsError, fn -> Payments.get_payment!(scope, payment.id) end
    end

    test "delete_payment/2 with invalid scope returns unauthorized error" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      payment = payment_fixture(scope)
      assert {:error, :unauthorized} = Payments.delete_payment(other_scope, payment)
    end

    test "change_payment/2 returns a payment changeset" do
      scope = user_scope_fixture()
      payment = payment_fixture(scope)
      assert %Ecto.Changeset{} = Payments.change_payment(scope, payment)
    end

    test "create_payment/2 with type :miscellaneous and valid category creates a miscellaneous payment" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope, %{tenant_id: scope.user.id})

      valid_attrs = %{
        status: :pending,
        amount: "250.00",
        notes: "Security deposit",
        contract_id: contract.id,
        type: :miscellaneous,
        category: :deposit
      }

      assert {:ok, %Payment{} = payment} = Payments.create_payment(scope, valid_attrs)
      assert payment.status == :pending
      assert payment.amount == Decimal.new("250.00")
      assert payment.notes == "Security deposit"
      assert payment.type == :miscellaneous
      assert payment.category == :deposit
      assert payment.payment_number == nil
      assert payment.user_id == scope.user.id
      assert payment.contract_id == contract.id
    end

    test "create_payment/2 with type :miscellaneous and missing category returns error" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope, %{tenant_id: scope.user.id})

      invalid_attrs = %{
        status: :pending,
        amount: "250.00",
        notes: "Security deposit",
        contract_id: contract.id,
        type: :miscellaneous
      }

      assert {:error, %Ecto.Changeset{} = changeset} =
               Payments.create_payment(scope, invalid_attrs)

      assert "can't be blank" in errors_on(changeset).category
    end

    test "create_payment/2 with type :rent ignores category and sets it to nil" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope, %{tenant_id: scope.user.id})

      attrs = %{
        status: :pending,
        amount: "1200.00",
        payment_number: 1,
        notes: "Monthly rent",
        contract_id: contract.id,
        type: :rent,
        category: :deposit
      }

      assert {:ok, %Payment{} = payment} = Payments.create_payment(scope, attrs)
      assert payment.type == :rent
      assert payment.category == nil
      assert payment.payment_number == 1
    end

    test "miscellaneous payments are excluded from rent financial analytics" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope, %{tenant_id: scope.user.id, rent: "1000.00"})

      # Create an accepted rent payment
      {:ok, rent_payment} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          amount: "500.00",
          payment_number: 1,
          type: :rent
        })

      # Accept the rent payment
      {:ok, _} = Payments.accept_payment(scope, rent_payment)

      # Create a miscellaneous payment for same amount
      {:ok, misc_payment} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          amount: "500.00",
          type: :miscellaneous,
          category: :deposit
        })

      # Accept the misc payment
      {:ok, _} = Payments.accept_payment(scope, misc_payment)

      # total_accepted_for_month should only count the rent payment
      assert Decimal.equal?(
               Payments.total_accepted_for_month(scope, contract.id, 1),
               Decimal.new("500.00")
             )

      # total_rent_collected should only count the rent payment
      # (misc payments have no payment_number, so they won't be included in past periods)
      assert Decimal.equal?(
               Payments.total_rent_collected(scope, contract),
               Decimal.new("500.00")
             )

      # received_income_by_month should only include rent payments
      income_by_month = Payments.received_income_by_month(scope)
      assert map_size(income_by_month) == 1

      {_month, total} = Enum.at(income_by_month, 0)
      assert Decimal.equal?(total, Decimal.new("500.00"))
    end
  end

  describe "payment management" do
    alias Vivvo.Payments.Payment

    import Vivvo.AccountsFixtures, only: [user_scope_fixture: 0]
    import Vivvo.ContractsFixtures, only: [contract_fixture: 2]
    import Vivvo.PaymentsFixtures

    test "accept_payment/2 updates status to accepted and clears rejection_reason" do
      scope = user_scope_fixture()
      payment = payment_fixture(scope)

      assert {:ok, %Payment{status: :accepted, rejection_reason: nil}} =
               Payments.accept_payment(scope, payment)

      assert Payments.get_payment!(scope, payment.id).status == :accepted
      assert Payments.get_payment!(scope, payment.id).rejection_reason == nil
    end

    test "accept_payment/2 with invalid scope returns unauthorized error" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      payment = payment_fixture(scope)

      assert {:error, :unauthorized} = Payments.accept_payment(other_scope, payment)
    end

    test "reject_payment/3 requires and sets rejection reason" do
      scope = user_scope_fixture()
      payment = payment_fixture(scope)

      assert {:ok, %Payment{status: :rejected, rejection_reason: "Invalid amount"}} =
               Payments.reject_payment(scope, payment, "Invalid amount")

      assert Payments.get_payment!(scope, payment.id).status == :rejected
      assert Payments.get_payment!(scope, payment.id).rejection_reason == "Invalid amount"
    end

    test "reject_payment/3 with invalid scope returns unauthorized error" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      payment = payment_fixture(scope)

      assert {:error, :unauthorized} = Payments.reject_payment(other_scope, payment, "reason")
    end
  end

  describe "payment queries" do
    alias Vivvo.Payments.Payment

    import Vivvo.AccountsFixtures, only: [user_scope_fixture: 0]
    import Vivvo.ContractsFixtures, only: [contract_fixture: 2]
    import Vivvo.PaymentsFixtures

    test "list_payments_for_tenant/1 returns payments for tenant's contracts" do
      owner_scope = user_scope_fixture()
      tenant_scope = user_scope_fixture()

      contract =
        contract_fixture(owner_scope, %{
          tenant_id: tenant_scope.user.id,
          rent: "1000.00"
        })

      # Payments are created by tenants, not owners
      payment_fixture(tenant_scope, %{
        contract_id: contract.id,
        payment_number: 1,
        amount: "500.00"
      })

      assert [%Payment{}] = Payments.list_payments_for_tenant(tenant_scope)
    end

    test "list_payments_for_tenant/1 returns empty when tenant has no contracts" do
      tenant_scope = user_scope_fixture()
      assert [] = Payments.list_payments_for_tenant(tenant_scope)
    end

    test "list_payments_for_contract/2 returns payments for specific contract" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope, %{tenant_id: scope.user.id, rent: "1000.00"})

      payment_fixture(scope, %{
        contract_id: contract.id,
        payment_number: 1,
        amount: "500.00"
      })

      assert [%Payment{}] = Payments.list_payments_for_contract(scope, contract.id)
    end

    test "total_accepted_for_month/3 sums only accepted payments" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope, %{tenant_id: scope.user.id, rent: "1000.00"})

      {:ok, accepted} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "500.00"
        })

      {:ok, _} = Payments.accept_payment(scope, accepted)

      payment_fixture(scope, %{
        contract_id: contract.id,
        payment_number: 1,
        amount: "300.00"
      })

      {:ok, rejected} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "100.00"
        })

      {:ok, _} = Payments.reject_payment(scope, rejected, "Invalid amount")

      assert Decimal.equal?(
               Payments.total_accepted_for_month(scope, contract.id, 1),
               Decimal.new("500.00")
             )
    end

    test "total_accepted_for_month/3 returns zero when no accepted payments" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope, %{tenant_id: scope.user.id})

      assert Decimal.equal?(
               Payments.total_accepted_for_month(scope, contract.id, 1),
               Decimal.new("0")
             )
    end

    test "month_fully_paid?/2 returns true when sum >= rent" do
      scope = user_scope_fixture()

      contract =
        contract_fixture(scope, %{
          tenant_id: scope.user.id,
          rent: "1000.00"
        })

      {:ok, payment} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "1000.00"
        })

      {:ok, _} = Payments.accept_payment(scope, payment)

      assert Payments.month_fully_paid?(scope, contract, 1)
    end

    test "month_fully_paid?/2 returns false when sum < rent" do
      scope = user_scope_fixture()

      contract =
        contract_fixture(scope, %{
          tenant_id: scope.user.id,
          rent: "1000.00"
        })

      {:ok, payment} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "500.00"
        })

      {:ok, _} = Payments.accept_payment(scope, payment)

      refute Payments.month_fully_paid?(scope, contract, 1)
    end

    test "get_month_status/2 returns :paid when fully paid" do
      scope = user_scope_fixture()

      contract =
        contract_fixture(scope, %{
          tenant_id: scope.user.id,
          rent: "1000.00"
        })

      {:ok, payment} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "1000.00"
        })

      {:ok, _} = Payments.accept_payment(scope, payment)

      assert Payments.get_month_status(scope, contract, 1) == :paid
    end

    test "get_month_status/2 returns :partial when partially paid" do
      scope = user_scope_fixture()

      contract =
        contract_fixture(scope, %{
          tenant_id: scope.user.id,
          rent: "1000.00"
        })

      {:ok, payment} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "500.00"
        })

      {:ok, _} = Payments.accept_payment(scope, payment)

      assert Payments.get_month_status(scope, contract, 1) == :partial
    end

    test "get_month_status/2 returns :unpaid when no payments" do
      scope = user_scope_fixture()
      contract = contract_fixture(scope, %{tenant_id: scope.user.id, rent: "1000.00"})

      assert Payments.get_month_status(scope, contract, 1) == :unpaid
    end
  end

  describe "payment period calculations" do
    import Vivvo.AccountsFixtures, only: [user_scope_fixture: 0]
    import Vivvo.ContractsFixtures, only: [contract_fixture: 2, contract_fixture: 3]
    import Vivvo.PaymentsFixtures

    test "payment_target_month/2 calculates correct month for payment_number 1" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Use a future month for testing
      future_start = Date.add(today, 30)

      contract =
        contract_fixture(scope, %{
          start_date: future_start,
          end_date: Date.add(future_start, 365)
        })

      assert Payments.payment_target_month(contract, 1) ==
               Date.new!(future_start.year, future_start.month, 1)
    end

    test "payment_target_month/2 calculates correct month for payment_number 2" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Use a future month for testing - start 30 days from now
      future_start = Date.add(today, 30)
      # Get the first day of the month that's 30 days after the start month
      next_month_date = Date.add(future_start, 31)

      contract =
        contract_fixture(scope, %{
          start_date: future_start,
          end_date: Date.add(future_start, 365)
        })

      assert Payments.payment_target_month(contract, 2) ==
               Date.new!(next_month_date.year, next_month_date.month, 1)
    end

    test "payment_target_month/2 handles year boundary correctly" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      # Use last year for start to test year boundary
      start_year = today.year - 1

      contract =
        contract_fixture(
          scope,
          %{
            start_date: Date.new!(start_year, 11, 1),
            end_date: Date.new!(today.year, 12, 31)
          },
          past_start_date?: true,
          update_factor: Decimal.new("0.0")
        )

      # Payment 1 = November start_year
      assert Payments.payment_target_month(contract, 1) == Date.new!(start_year, 11, 1)
      # Payment 2 = December start_year
      assert Payments.payment_target_month(contract, 2) == Date.new!(start_year, 12, 1)
      # Payment 3 = January current year
      assert Payments.payment_target_month(contract, 3) == Date.new!(today.year, 1, 1)
    end

    test "received_income_for_month/2 counts payment based on period, not submission time" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Contract starting in the past (January of current year)
      contract =
        contract_fixture(
          scope,
          %{
            start_date: Date.new!(today.year, 1, 15),
            end_date: Date.new!(today.year, 12, 15),
            rent: "1000.00",
            tenant_id: scope.user.id,
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("0.0")
        )

      # Payment for February (payment_number 2) but submitted in March
      # This simulates a late payment
      {:ok, payment} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 2,
          amount: "1000.00",
          status: :pending,
          notes: "Late payment for February"
        })

      # Accept the payment (would be done in March in real scenario)
      {:ok, _} = Payments.accept_payment(scope, payment)

      # Payment should be counted in February, not March
      february_income =
        Payments.received_income_for_month(scope, Date.new!(today.year, 2, 1))

      march_income =
        Payments.received_income_for_month(scope, Date.new!(today.year, 3, 1))

      assert Decimal.equal?(february_income, Decimal.new("1000.00"))
      assert Decimal.equal?(march_income, Decimal.new("0"))
    end

    test "received_income_for_month/2 handles multiple late payments correctly" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Contract starting in the past (January of current year)
      contract =
        contract_fixture(
          scope,
          %{
            start_date: Date.new!(today.year, 1, 1),
            end_date: Date.new!(today.year, 12, 31),
            rent: "1000.00",
            tenant_id: scope.user.id,
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("0.0")
        )

      # January payment (on time) - create and accept
      {:ok, jan_payment} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "1000.00"
        })

      {:ok, _} = Payments.accept_payment(scope, jan_payment)

      # February payment (late, submitted in March) - create and accept
      {:ok, feb_payment} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 2,
          amount: "800.00"
        })

      {:ok, _} = Payments.accept_payment(scope, feb_payment)

      # Another partial payment for February - create and accept
      {:ok, feb_payment2} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 2,
          amount: "200.00"
        })

      {:ok, _} = Payments.accept_payment(scope, feb_payment2)

      # Check that January has correct income
      january_income =
        Payments.received_income_for_month(scope, Date.new!(today.year, 1, 1))

      assert Decimal.equal?(january_income, Decimal.new("1000.00"))

      # Check that February has both payments summed
      february_income =
        Payments.received_income_for_month(scope, Date.new!(today.year, 2, 1))

      assert Decimal.equal?(february_income, Decimal.new("1000.00"))
    end

    test "collection_rate_for_month/2 calculates correctly with late payments" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Contract starting in February (in the past, use past_start_date option)
      contract =
        contract_fixture(
          scope,
          %{
            start_date: Date.new!(today.year, 2, 1),
            end_date: Date.new!(today.year, 12, 31),
            rent: "1000.00",
            tenant_id: scope.user.id,
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("0.0")
        )

      # Partial payment for February (payment_number 1) - create and accept
      {:ok, payment} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "700.00"
        })

      {:ok, _} = Payments.accept_payment(scope, payment)

      # Expected: 1000, Received: 700, Rate: 70%
      rate =
        Payments.collection_rate_for_month(scope, Date.new!(today.year, 2, 1))

      assert_in_delta rate, 70.0, 0.01
    end

    test "outstanding_balance_for_month/2 calculates correctly with late payments" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Contract starting in February (in the past, use past_start_date option)
      contract =
        contract_fixture(
          scope,
          %{
            start_date: Date.new!(today.year, 2, 1),
            end_date: Date.new!(today.year, 12, 31),
            rent: "1000.00",
            tenant_id: scope.user.id,
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("0.0")
        )

      # Partial payment for February - create and accept
      {:ok, payment} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "400.00"
        })

      {:ok, _} = Payments.accept_payment(scope, payment)

      # Outstanding should be 1000 - 400 = 600
      outstanding =
        Payments.outstanding_balance_for_month(scope, Date.new!(today.year, 2, 1))

      assert Decimal.equal?(outstanding, Decimal.new("600.00"))
    end

    test "received_income_by_month/1 groups payments by target month" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Contract starting in January (in the past, use past_start_date option)
      contract =
        contract_fixture(
          scope,
          %{
            start_date: Date.new!(today.year, 1, 1),
            end_date: Date.new!(today.year, 12, 31),
            rent: "1000.00",
            tenant_id: scope.user.id,
            index_type: :icl,
            rent_period_duration: 12
          },
          past_start_date?: true,
          update_factor: Decimal.new("0.0")
        )

      # Create and accept payments for different months
      {:ok, payment1} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "1000.00"
        })

      {:ok, _} = Payments.accept_payment(scope, payment1)

      {:ok, payment2} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 2,
          amount: "500.00"
        })

      {:ok, _} = Payments.accept_payment(scope, payment2)

      {:ok, payment3} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 2,
          amount: "500.00"
        })

      {:ok, _} = Payments.accept_payment(scope, payment3)

      income_by_month = Payments.received_income_by_month(scope)

      assert Decimal.equal?(
               income_by_month[Date.new!(today.year, 1, 1)],
               Decimal.new("1000.00")
             )

      assert Decimal.equal?(
               income_by_month[Date.new!(today.year, 2, 1)],
               Decimal.new("1000.00")
             )
    end
  end
end
