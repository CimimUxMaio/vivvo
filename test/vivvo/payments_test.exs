defmodule Vivvo.PaymentsTest do
  use Vivvo.DataCase

  alias Vivvo.Payments

  describe "payments" do
    alias Vivvo.Payments.Payment

    import Vivvo.AccountsFixtures, only: [user_scope_fixture: 0]
    import Vivvo.ContractsFixtures, only: [contract_fixture: 2]
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

    test "update_payment/3 with valid data updates the payment" do
      scope = user_scope_fixture()
      payment = payment_fixture(scope)

      update_attrs = %{
        status: :accepted,
        amount: "456.7",
        payment_number: 43,
        notes: "some updated notes"
      }

      assert {:ok, %Payment{} = payment} = Payments.update_payment(scope, payment, update_attrs)
      assert payment.status == :accepted
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
  end

  describe "payment management" do
    alias Vivvo.Payments.Payment

    import Vivvo.AccountsFixtures, only: [user_scope_fixture: 0]
    import Vivvo.ContractsFixtures, only: [contract_fixture: 2]
    import Vivvo.PaymentsFixtures

    test "accept_payment/2 updates status to accepted and clears rejection_reason" do
      scope = user_scope_fixture()

      payment =
        payment_fixture(scope, %{
          status: :pending,
          rejection_reason: "previous rejection"
        })

      assert {:ok, %Payment{status: :accepted, rejection_reason: nil}} =
               Payments.accept_payment(scope, payment)

      assert Payments.get_payment!(scope, payment.id).status == :accepted
      assert Payments.get_payment!(scope, payment.id).rejection_reason == nil
    end

    test "accept_payment/2 with invalid scope returns unauthorized error" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      payment = payment_fixture(scope, %{status: :pending})

      assert {:error, :unauthorized} = Payments.accept_payment(other_scope, payment)
    end

    test "reject_payment/3 requires and sets rejection reason" do
      scope = user_scope_fixture()
      payment = payment_fixture(scope, %{status: :pending})

      assert {:ok, %Payment{status: :rejected, rejection_reason: "Invalid amount"}} =
               Payments.reject_payment(scope, payment, "Invalid amount")

      assert Payments.get_payment!(scope, payment.id).status == :rejected
      assert Payments.get_payment!(scope, payment.id).rejection_reason == "Invalid amount"
    end

    test "reject_payment/3 with invalid scope returns unauthorized error" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      payment = payment_fixture(scope, %{status: :pending})

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

      payment_fixture(scope, %{
        contract_id: contract.id,
        payment_number: 1,
        amount: "500.00",
        status: :accepted
      })

      payment_fixture(scope, %{
        contract_id: contract.id,
        payment_number: 1,
        amount: "300.00",
        status: :pending
      })

      payment_fixture(scope, %{
        contract_id: contract.id,
        payment_number: 1,
        amount: "100.00",
        status: :rejected,
        rejection_reason: "Invalid amount"
      })

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

      payment_fixture(scope, %{
        contract_id: contract.id,
        payment_number: 1,
        amount: "1000.00",
        status: :accepted
      })

      assert Payments.month_fully_paid?(scope, contract, 1)
    end

    test "month_fully_paid?/2 returns false when sum < rent" do
      scope = user_scope_fixture()

      contract =
        contract_fixture(scope, %{
          tenant_id: scope.user.id,
          rent: "1000.00"
        })

      payment_fixture(scope, %{
        contract_id: contract.id,
        payment_number: 1,
        amount: "500.00",
        status: :accepted
      })

      refute Payments.month_fully_paid?(scope, contract, 1)
    end

    test "get_month_status/2 returns :paid when fully paid" do
      scope = user_scope_fixture()

      contract =
        contract_fixture(scope, %{
          tenant_id: scope.user.id,
          rent: "1000.00"
        })

      payment_fixture(scope, %{
        contract_id: contract.id,
        payment_number: 1,
        amount: "1000.00",
        status: :accepted
      })

      assert Payments.get_month_status(scope, contract, 1) == :paid
    end

    test "get_month_status/2 returns :partial when partially paid" do
      scope = user_scope_fixture()

      contract =
        contract_fixture(scope, %{
          tenant_id: scope.user.id,
          rent: "1000.00"
        })

      payment_fixture(scope, %{
        contract_id: contract.id,
        payment_number: 1,
        amount: "500.00",
        status: :accepted
      })

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

      # January payment (on time)
      {:ok, _jan_payment} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "1000.00",
          status: :accepted
        })

      # February payment (late, submitted in March)
      {:ok, _feb_payment} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 2,
          amount: "800.00",
          status: :accepted
        })

      # Another partial payment for February
      {:ok, _feb_payment2} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 2,
          amount: "200.00",
          status: :accepted
        })

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

      # Partial payment for February (payment_number 1)
      {:ok, _payment} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "700.00",
          status: :accepted
        })

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

      # Partial payment for February
      {:ok, _payment} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "400.00",
          status: :accepted
        })

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

      # Create payments for different months
      {:ok, _} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 1,
          amount: "1000.00",
          status: :accepted
        })

      {:ok, _} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 2,
          amount: "500.00",
          status: :accepted
        })

      {:ok, _} =
        Payments.create_payment(scope, %{
          contract_id: contract.id,
          payment_number: 2,
          amount: "500.00",
          status: :accepted
        })

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
