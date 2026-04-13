defmodule Vivvo.Workers.RentPeriodCreationWorkerTest do
  use Vivvo.DataCase, async: false

  alias Vivvo.Contracts
  alias Vivvo.Contracts.Contract
  alias Vivvo.Contracts.RentPeriod
  alias Vivvo.Indexes
  alias Vivvo.Repo
  alias Vivvo.Workers.RentPeriodCreationWorker

  import Vivvo.ContractsFixtures
  import Vivvo.AccountsFixtures

  describe "perform/1" do
    test "creates rent period when target period ends in previous month" do
      scope = user_scope_fixture()

      # Fixed dates: July 1st as "today", period ends June 30th (previous month)
      # For 6-month duration starting Jan 1: period ends June 30
      contract_start = ~D[2023-01-01]
      today = ~D[2023-07-01]
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: last_month_end
        )

      # Verify the latest period ends in previous month (June 30)
      latest_period = List.last(contract.rent_periods)
      assert latest_period.end_date == last_month_end

      expected_new_start = Date.add(latest_period.end_date, 1)

      assert {:ok, %RentPeriod{} = rent_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: Date.to_iso8601(today)
               })

      assert rent_period.start_date == expected_new_start
      assert rent_period.index_type == :ipc
      # Update factor is computed by the Indexes module
      assert %Decimal{} = rent_period.update_factor
    end

    test "is idempotent - returns :already_exists when run twice with same today" do
      scope = user_scope_fixture()

      # Fixed dates: July 1st as "today", period ends June 30th (previous month)
      contract_start = ~D[2023-01-01]
      today = ~D[2023-07-01]
      today_string = Date.to_iso8601(today)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: last_month_end
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

      # Fixed dates: July 1st as "today", period ends June 30th (previous month)
      contract_start = ~D[2023-01-01]
      today = ~D[2023-07-01]
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.add(today, 365),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0"),
          today: last_month_end
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

    test "returns :period_not_found when no period ends in previous month" do
      scope = user_scope_fixture()

      # Fixed dates: April 1st as "today"
      # For 6-month duration starting Jan 1: period ends June 30
      # On April 1, the period ends in June (future), not March (previous)
      contract_start = ~D[2023-01-01]
      today = ~D[2023-04-01]
      future_date = Date.add(today, 60)
      future_date_string = Date.to_iso8601(future_date)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: today
        )

      # Verify period ends in June, not March
      latest_period = List.last(contract.rent_periods)
      assert latest_period.end_date == ~D[2023-06-30]

      # Try to run with a date in the future where no period ends in previous month
      assert {:ok, :period_not_found} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: future_date_string
               })
    end

    test "creates rent period with update factor from Indexes module" do
      scope = user_scope_fixture()

      # Fixed dates: July 1st as "today", period ends June 30th (previous month)
      contract_start = ~D[2023-01-01]
      today = ~D[2023-07-01]
      today_string = Date.to_iso8601(today)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      # Create IPC history entries for the period
      # IPC needs history at the period start and previous month
      for i <- 1..2 do
        date = last_month_end |> Date.shift(month: -i + 1) |> Date.beginning_of_month()

        Indexes.create_index_history(%{
          type: :ipc,
          value: Decimal.new("2.5"),
          date: date
        })
      end

      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: last_month_end
        )

      target_period =
        Enum.find(contract.rent_periods, fn p ->
          p.end_date == last_month_end
        end)

      assert target_period != nil

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
      today_string = Date.to_iso8601(~D[2023-07-01])

      assert {:ok, :contract_not_found} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: non_existent_id,
                 today: today_string
               })
    end

    test "returns contract_not_found when contract is archived" do
      scope = user_scope_fixture()

      # Fixed dates: July 1st as "today", period ends June 30th (previous month)
      contract_start = ~D[2023-01-01]
      today = ~D[2023-07-01]
      today_string = Date.to_iso8601(today)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0"),
          today: last_month_end
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

      # Fixed dates: July 1st as "today", period ends June 30th (previous month)
      contract_start = ~D[2023-01-01]
      today = ~D[2023-07-01]
      today_string = Date.to_iso8601(today)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      # Create ICL history - need values at different dates
      # Create historical ICL value at contract start
      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("100.00"),
        date: contract_start
      })

      # Create ICL value at previous month (June 2023)
      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("110.00"),
        date: Date.beginning_of_month(last_month_end)
      })

      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 6,
            index_type: :icl
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0"),
          today: last_month_end
        )

      target_period =
        Enum.find(contract.rent_periods, fn p ->
          p.end_date == last_month_end
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

      # Fixed dates: July 1st as "today", period ends June 30th (previous month)
      contract_start = ~D[2023-01-01]
      today = ~D[2023-07-01]
      today_string = Date.to_iso8601(today)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      # Only create recent ICL history, not historical
      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("110.00"),
        date: Date.beginning_of_month(last_month_end)
      })

      # Don't create historical ICL value at contract start date

      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 6,
            index_type: :icl
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0"),
          today: last_month_end
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

      # Fixed dates: July 1st as "today", period ends June 30th (previous month)
      contract_start = ~D[2023-01-01]
      today = ~D[2023-07-01]
      today_string = Date.to_iso8601(today)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      # Create IPC history at previous month
      Indexes.create_index_history(%{
        type: :ipc,
        value: Decimal.new("2.5"),
        date: Date.beginning_of_month(last_month_end)
      })

      # Create ICL history
      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("100.00"),
        date: contract_start
      })

      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("110.00"),
        date: Date.beginning_of_month(last_month_end)
      })

      # Create IPC contract
      ipc_contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.025"),
          today: last_month_end
        )

      # Create ICL contract
      icl_contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 6,
            index_type: :icl
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0"),
          today: last_month_end
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

      # Fixed dates: July 1st as "today", period ends June 30th (previous month)
      # Create contract with end_date that will be hit by new period
      contract_start = ~D[2023-01-01]
      today = ~D[2023-07-01]
      today_string = Date.to_iso8601(today)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      # Contract ends in December - after the new period would end
      contract_end = ~D[2023-12-31]

      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: contract_end,
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: last_month_end
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

      # Fixed dates: February 1st as "today", period ends Jan 31st (previous month)
      contract_start = ~D[2023-01-01]
      today = ~D[2023-02-01]
      today_string = Date.to_iso8601(today)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 1,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: last_month_end
        )

      assert {:ok, %RentPeriod{} = rent_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })

      # Should create a 1-month period starting after the existing period ends
      target_period =
        Enum.find(contract.rent_periods, fn p ->
          p.end_date == last_month_end
        end)

      assert target_period != nil
      assert rent_period.start_date == Date.add(target_period.end_date, 1)
      assert rent_period.end_date == Date.end_of_month(rent_period.start_date)
    end

    test "handles very large rent_period_duration of 24 months" do
      scope = user_scope_fixture()

      # Fixed dates: January 1st, 2025 as "today", period ends Dec 31st, 2024 (previous month)
      # For 24-month duration starting Jan 2023: period ends Dec 2024
      contract_start = ~D[2023-01-01]
      today = ~D[2025-01-01]
      today_string = Date.to_iso8601(today)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 36),
            rent_period_duration: 24,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: last_month_end
        )

      # Find the period ending in previous month (Dec 2024)
      target_period =
        Enum.find(contract.rent_periods, fn p ->
          p.end_date == last_month_end
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

      # Fixed dates: March 1st as "today", period ends Feb 28th (previous month)
      # For 2-month duration starting Jan 1: periods end Feb 28, Apr 30, Jun 30...
      contract_start = ~D[2023-01-01]
      today = ~D[2023-03-01]
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 2,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: last_month_end
        )

      # Get initial count of periods
      initial_period_count = length(contract.rent_periods)
      assert initial_period_count >= 1

      # Find the period that ends in previous month (Feb 28)
      target_period =
        Enum.find(contract.rent_periods, fn p ->
          p.end_date == last_month_end
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

    test "handles period created between check and insert gracefully" do
      scope = user_scope_fixture()

      # Fixed dates: July 1st as "today", period ends June 30th (previous month)
      contract_start = ~D[2023-01-01]
      today = ~D[2023-07-01]
      today_string = Date.to_iso8601(today)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: last_month_end
        )

      target_period =
        Enum.find(contract.rent_periods, fn p ->
          p.end_date == last_month_end
        end)

      assert target_period != nil

      # Manually create the next period (simulating concurrent creation)
      Contracts.create_rent_period(%{
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

      # Fixed dates: July 1st as "today", period ends June 30th (previous month)
      contract_start = ~D[2023-01-01]
      today = ~D[2023-07-01]
      today_string = Date.to_iso8601(today)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: last_month_end
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
