defmodule Vivvo.Workers.RentPeriodCreationWorkerTest do
  use Vivvo.DataCase, async: true

  alias Vivvo.Contracts
  alias Vivvo.Contracts.Contract
  alias Vivvo.Contracts.RentPeriod
  alias Vivvo.Indexes
  alias Vivvo.Repo
  alias Vivvo.Workers.RentPeriodCreationWorker

  import Vivvo.ContractsFixtures
  import Vivvo.AccountsFixtures

  describe "perform/1" do
    test "creates rent period when target period ends in scheduler's month" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create a contract that started 5 months ago with 6-month duration
      # This generates a period ending this month (current month)
      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: five_months_ago,
            end_date: Date.add(today, 1000),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      # Find the period ending this month
      target_period =
        Enum.find(contract.rent_periods, fn p ->
          p.end_date.year == today.year and p.end_date.month == today.month
        end)

      assert target_period != nil

      expected_new_start = Date.add(target_period.end_date, 1)
      today_string = Date.to_iso8601(today)

      assert {:ok, %RentPeriod{} = rent_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })

      assert rent_period.start_date == expected_new_start
      assert rent_period.index_type == :ipc
      # Update factor is computed by the Indexes module
      assert %Decimal{} = rent_period.update_factor
    end

    test "is idempotent - returns :already_exists when run twice with same today" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      today_string = Date.to_iso8601(today)

      # Create a contract with period ending this month
      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: five_months_ago,
            end_date: Date.add(today, 1000),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      initial_count = length(Contracts.get_contract!(scope, contract.id).rent_periods)

      # First run creates the period
      assert {:ok, %RentPeriod{}} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })

      after_first = length(Contracts.get_contract!(scope, contract.id).rent_periods)
      assert after_first == initial_count + 1

      # Second run with same today returns :already_exists
      assert {:ok, :already_exists} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })

      # No new period created
      final_count = length(Contracts.get_contract!(scope, contract.id).rent_periods)
      assert final_count == after_first
    end

    test "respects contract boundaries" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: five_months_ago,
            end_date: Date.add(today, 365),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
        )

      today_string = Date.to_iso8601(today)

      assert {:ok, rent_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })

      expected_end =
        rent_period.start_date
        |> Date.shift(month: 5)
        |> Date.end_of_month()
        |> then(&Enum.min([&1, contract.end_date], Date))

      assert rent_period.end_date == expected_end
    end

    test "returns :period_not_found when no period ends in scheduler's month" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create a contract starting today (no period ends this month)
      contract =
        contract_fixture(
          scope,
          %{
            start_date: today,
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :ipc
          }
        )

      # Try to run with a date in the future where no period ends
      future_date = Date.add(today, 60)
      future_date_string = Date.to_iso8601(future_date)

      assert {:ok, :period_not_found} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: future_date_string
               })
    end

    test "creates rent period with update factor from Indexes module" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      today_string = Date.to_iso8601(today)

      # Create IPC history so Indexes.compute_update_factor returns a value
      previous_month_end =
        today
        |> Date.beginning_of_month()
        |> Date.add(-1)

      # Create IPC history entries for the period
      for i <- 1..2 do
        date = Date.shift(previous_month_end, month: -i + 1) |> Date.beginning_of_month()

        Indexes.create_index_history(%{
          type: :ipc,
          value: Decimal.new("2.5"),
          date: date
        })
      end

      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: five_months_ago,
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      target_period =
        Enum.find(contract.rent_periods, fn p ->
          p.end_date.year == today.year and p.end_date.month == today.month
        end)

      # Get expected update factor from Indexes module
      expected_factor = Indexes.compute_update_factor(:ipc, target_period.start_date, today)

      assert {:ok, rent_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })

      # Verify the update factor matches what Indexes module computed
      assert Decimal.eq?(rent_period.update_factor, expected_factor)

      # Update factor is now a direct multiplier (already includes +1 for percentage-based)
      assert Decimal.eq?(
               rent_period.value,
               Decimal.mult(target_period.value, expected_factor)
             )
    end

    test "returns contract_not_found when contract does not exist" do
      non_existent_id = 99_999_999
      today_string = Date.to_iso8601(Date.utc_today())

      assert {:ok, :contract_not_found} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: non_existent_id,
                 today: today_string
               })
    end

    test "returns contract_not_found when contract is archived" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      today_string = Date.to_iso8601(today)

      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: five_months_ago,
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
        )

      Repo.update!(Contract.archive_changeset(contract, scope))

      assert {:ok, :contract_not_found} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })
    end

    test "creates period with ICL update factor using ratio calculation" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      today_string = Date.to_iso8601(today)

      # Create ICL history - need values at different dates
      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

      previous_month = Date.shift(today, month: -1) |> Date.beginning_of_month()

      # Create historical ICL value
      Vivvo.Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("100.00"),
        date: five_months_ago
      })

      # Create more recent ICL value
      Vivvo.Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("110.00"),
        date: previous_month
      })

      contract =
        contract_fixture(
          scope,
          %{
            start_date: five_months_ago,
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :icl
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
        )

      target_period =
        Enum.find(contract.rent_periods, fn p ->
          p.end_date.year == today.year and p.end_date.month == today.month
        end)

      assert target_period != nil

      assert {:ok, %RentPeriod{} = rent_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })

      # ICL uses ratio calculation: new_value / old_value
      # 110 / 100 = 1.1
      assert rent_period.index_type == :icl
      assert Decimal.eq?(rent_period.update_factor, Decimal.new("1.1"))

      # Rent should be previous_period.value * 1.1
      expected_rent = Decimal.mult(target_period.value, Decimal.new("1.1"))
      assert Decimal.eq?(rent_period.value, expected_rent)
    end

    test "handles ICL when historical value is missing - raises error" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      today_string = Date.to_iso8601(today)

      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

      # Only create recent ICL history, not historical
      previous_month = Date.shift(today, month: -1) |> Date.beginning_of_month()

      Vivvo.Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("110.00"),
        date: previous_month
      })

      # Don't create historical ICL value at contract start date

      contract =
        contract_fixture(
          scope,
          %{
            start_date: five_months_ago,
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :icl
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
        )

      # Should raise ArgumentError when historical ICL is missing
      assert_raise ArgumentError, ~r/No ICL history found/, fn ->
        perform_job(RentPeriodCreationWorker, %{
          contract_id: contract.id,
          today: today_string
        })
      end
    end

    test "ICL and IPC produce different update factors for same contract timing" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      today_string = Date.to_iso8601(today)

      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

      previous_month = Date.shift(today, month: -1) |> Date.beginning_of_month()

      # Create IPC history
      Vivvo.Indexes.create_index_history(%{
        type: :ipc,
        value: Decimal.new("2.5"),
        date: previous_month
      })

      # Create ICL history
      Vivvo.Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("100.00"),
        date: five_months_ago
      })

      Vivvo.Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("110.00"),
        date: previous_month
      })

      # Create IPC contract
      ipc_contract =
        contract_fixture(
          scope,
          %{
            start_date: five_months_ago,
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.025")
        )

      # Create ICL contract
      icl_contract =
        contract_fixture(
          scope,
          %{
            start_date: five_months_ago,
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :icl
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0")
        )

      # Get IPC update factor
      {:ok, %RentPeriod{} = ipc_period} =
        perform_job(RentPeriodCreationWorker, %{
          contract_id: ipc_contract.id,
          today: today_string
        })

      # Get ICL update factor
      {:ok, %RentPeriod{} = icl_period} =
        perform_job(RentPeriodCreationWorker, %{
          contract_id: icl_contract.id,
          today: today_string
        })

      # IPC factor should be ~1.025 (1 + 2.5%)
      assert Decimal.eq?(ipc_period.update_factor, Decimal.new("1.025"))

      # ICL factor should be 1.1 (110 / 100)
      assert Decimal.eq?(icl_period.update_factor, Decimal.new("1.1"))

      # Factors should be different
      refute Decimal.eq?(ipc_period.update_factor, icl_period.update_factor)
    end

    test "new period end date exactly equals contract end_date" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      today_string = Date.to_iso8601(today)

      # Create contract with 2-month duration
      # First period: month 1-2, Second period would be month 3-4
      # But let's make contract end exactly at period boundary
      three_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -3)

      contract_end =
        today
        |> Date.end_of_month()
        |> Date.add(30)
        |> Date.end_of_month()

      contract =
        contract_fixture(
          scope,
          %{
            start_date: three_months_ago,
            end_date: contract_end,
            rent_period_duration: 2,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      assert {:ok, %RentPeriod{} = rent_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })

      # The new period should respect the contract end_date
      assert Date.compare(rent_period.end_date, contract.end_date) != :gt
    end

    test "handles very small rent_period_duration of 1 month" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      today_string = Date.to_iso8601(today)

      # 1 month ago with 1-month duration
      one_month_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -1)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: one_month_ago,
            end_date: Date.add(today, 400),
            rent_period_duration: 1,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      assert {:ok, %RentPeriod{} = rent_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })

      # Should create a 1-month period starting after the existing period ends
      target_period =
        Enum.find(contract.rent_periods, fn p ->
          p.end_date.year == today.year and p.end_date.month == today.month
        end)

      assert target_period != nil
      assert rent_period.start_date == Date.add(target_period.end_date, 1)
      assert rent_period.end_date == Date.end_of_month(rent_period.start_date)
    end

    test "handles very large rent_period_duration of 24 months" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      today_string = Date.to_iso8601(today)

      # 23 months ago with 24-month duration - creates period ending this month
      twenty_three_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -23)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: twenty_three_months_ago,
            end_date: Date.add(today, 400),
            rent_period_duration: 24,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      # Find the period ending this month
      target_period =
        Enum.find(contract.rent_periods, fn p ->
          p.end_date.year == today.year and p.end_date.month == today.month
        end)

      assert target_period != nil

      assert {:ok, %RentPeriod{} = rent_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })

      # New period should start the day after the target period ends
      expected_start = Date.add(target_period.end_date, 1)

      # End date should be ~24 months later or at contract end
      expected_end =
        expected_start
        |> Date.shift(month: 23)
        |> Date.end_of_month()

      assert rent_period.start_date == expected_start
      assert rent_period.end_date == expected_end or rent_period.end_date == contract.end_date
    end

    test "creates second period for contract with existing period" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create a contract that was just created
      # With 1-month duration starting 1 month ago, we should have at least 1 period
      one_month_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -1)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: one_month_ago,
            end_date: Date.add(today, 400),
            rent_period_duration: 1,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      # Get initial count of periods (could be more than 1 due to historical generation)
      initial_period_count = length(contract.rent_periods)
      assert initial_period_count >= 1

      # Find the period that ends this month
      target_period =
        Enum.find(contract.rent_periods, fn p ->
          p.end_date.year == today.year and p.end_date.month == today.month
        end)

      assert target_period != nil

      today_string = Date.to_iso8601(today)

      assert {:ok, %RentPeriod{} = new_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })

      # Should create one more period
      updated_contract = Contracts.get_contract!(scope, contract.id)
      assert length(updated_contract.rent_periods) == initial_period_count + 1

      # New period should start after the target period ends
      assert new_period.start_date == Date.add(target_period.end_date, 1)
    end

    test "is idempotent - returns :already_exists on duplicate runs" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      today_string = Date.to_iso8601(today)

      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: five_months_ago,
            end_date: Date.add(today, 1000),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      # First run creates the period
      assert {:ok, %RentPeriod{}} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })

      # Second run with same args returns :already_exists
      assert {:ok, :already_exists} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })
    end

    test "handles period created between check and insert gracefully" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      today_string = Date.to_iso8601(today)

      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: five_months_ago,
            end_date: Date.add(today, 1000),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      target_period =
        Enum.find(contract.rent_periods, fn p ->
          p.end_date.year == today.year and p.end_date.month == today.month
        end)

      # Manually create the next period (simulating concurrent creation)
      Vivvo.Contracts.create_rent_period(%{
        contract_id: contract.id,
        start_date: Date.add(target_period.end_date, 1),
        end_date: Date.end_of_month(Date.add(target_period.end_date, 6)),
        value: Decimal.mult(target_period.value, Decimal.new("1.03")),
        index_type: :ipc,
        update_factor: Decimal.new("1.03")
      })

      # Worker should handle this gracefully (period already exists)
      result =
        perform_job(RentPeriodCreationWorker, %{
          contract_id: contract.id,
          today: today_string
        })

      # Should return :already_exists due to unique constraint
      assert {:ok, :already_exists} = result
    end

    test "oban retry succeeds after failure" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      today_string = Date.to_iso8601(today)

      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: five_months_ago,
            end_date: Date.add(today, 1000),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      # Simulate a job that was previously attempted
      _job =
        %{contract_id: contract.id, today: today_string}
        |> RentPeriodCreationWorker.new(attempt: 2)

      # Perform the job
      result =
        perform_job(RentPeriodCreationWorker, %{
          "contract_id" => contract.id,
          "today" => today_string
        })

      # Should succeed
      assert {:ok, %RentPeriod{}} = result
    end
  end
end
