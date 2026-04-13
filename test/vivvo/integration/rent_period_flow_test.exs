defmodule Vivvo.Integration.RentPeriodFlowTest do
  use Vivvo.DataCase, async: false

  alias Vivvo.Contracts
  alias Vivvo.Contracts.RentPeriod
  alias Vivvo.Indexes
  alias Vivvo.Repo
  alias Vivvo.Workers.RentPeriodCreationWorker
  alias Vivvo.Workers.RentPeriodSchedulerWorker

  import Vivvo.AccountsFixtures
  import Vivvo.ContractsFixtures

  describe "full monthly cycle" do
    test "scheduler → index fetch → queue jobs → creation → verify periods created" do
      scope = user_scope_fixture()

      # Fixed dates: July 1st as "today", period ends June 30th (previous month)
      # For 6-month duration starting Jan 1: period ends June 30
      contract_start = ~D[2023-01-01]
      today = ~D[2023-07-01]
      today_string = Date.to_iso8601(today)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      # Create IPC history at previous month (June 2023)
      Indexes.create_index_history(%{
        type: :ipc,
        value: Decimal.new("2.5"),
        date: Date.beginning_of_month(last_month_end)
      })

      # Create contract with period ending in previous month
      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 6,
            index_type: :ipc,
            rent: "1000.00"
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: last_month_end
        )

      # Verify the latest period ends in previous month (June 30)
      latest_period = List.last(contract.rent_periods)
      assert latest_period.end_date == last_month_end

      initial_period_count = length(contract.rent_periods)

      # Step 1: Scheduler runs on July 1st and finds contract with period ending in June
      assert {:ok, %{scheduled_count: 1}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => today_string})

      # Verify job was enqueued
      assert_enqueued(worker: RentPeriodCreationWorker)

      # Step 2: Process the queued job
      assert {:ok, %RentPeriod{} = new_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })

      # Step 3: Verify period was created
      updated_contract = Contracts.get_contract!(scope, contract.id)
      assert length(updated_contract.rent_periods) == initial_period_count + 1

      # Verify new period has correct index information
      assert new_period.index_type == :ipc
      assert %Decimal{} = new_period.update_factor
      # July 1st
      assert new_period.start_date == today
    end
  end

  describe "multi-period over time" do
    test "contract with multiple periods can have new periods created sequentially" do
      scope = user_scope_fixture()

      # Fixed dates: April 1st as "today", period ends March 31st (previous month)
      # For 3-month duration starting Jan 1: periods end Mar 31, Jun 30, Sep 30...
      # On April 1, the previous month's end is March 31 - which matches period end
      contract_start = ~D[2023-01-01]
      today = ~D[2023-04-01]
      today_string = Date.to_iso8601(today)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      # Create IPC history at previous month and earlier
      for i <- 0..3 do
        date = last_month_end |> Date.shift(month: -i) |> Date.beginning_of_month()

        Indexes.create_index_history(%{
          type: :ipc,
          value: Decimal.new("2.5"),
          date: date
        })
      end

      # Create contract - fixture auto-generates periods up to last_month_end
      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 3,
            index_type: :ipc,
            rent: "1000.00"
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: last_month_end
        )

      # Verify the latest period ends in previous month (March 31)
      latest_period = List.last(contract.rent_periods)
      assert latest_period.end_date == last_month_end

      initial_period_count = length(contract.rent_periods)

      # Scheduler run on April 1st - should find the contract
      assert {:ok, %{scheduled_count: 1}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => today_string})

      assert {:ok, %RentPeriod{} = new_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })

      # Verify new period was created with correct attributes
      contract_after = Contracts.get_contract!(scope, contract.id)
      assert length(contract_after.rent_periods) == initial_period_count + 1
      assert new_period.index_type == :ipc
      assert %Decimal{} = new_period.update_factor
      # April 1st
      assert new_period.start_date == today
    end
  end

  describe "mixed index types" do
    test "multiple contracts (IPC + ICL), verify correct factors applied" do
      scope = user_scope_fixture()

      # Fixed dates: July 1st as "today", period ends June 30th (previous month)
      # For 6-month duration starting Jan 1: period ends June 30
      contract_start = ~D[2023-01-01]
      today = ~D[2023-07-01]
      today_string = Date.to_iso8601(today)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      # Create IPC history at previous month (June 2023)
      Indexes.create_index_history(%{
        type: :ipc,
        value: Decimal.new("2.5"),
        date: Date.beginning_of_month(last_month_end)
      })

      # Create ICL history - need values at contract start and previous month
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

      # Create IPC contract with period ending in previous month
      ipc_contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 6,
            index_type: :ipc,
            rent: "1000.00"
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.025"),
          today: last_month_end
        )

      # Verify IPC period ends in previous month
      ipc_latest_period = List.last(ipc_contract.rent_periods)
      assert ipc_latest_period.end_date == last_month_end

      # Create ICL contract with period ending in previous month
      icl_contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 6,
            index_type: :icl,
            rent: "1000.00"
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.0"),
          today: last_month_end
        )

      # Verify ICL period ends in previous month
      icl_latest_period = List.last(icl_contract.rent_periods)
      assert icl_latest_period.end_date == last_month_end

      # Scheduler should pick up both contracts
      assert {:ok, %{scheduled_count: 2}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => today_string})

      assert Repo.aggregate(Oban.Job, :count) == 2

      # Process IPC job
      assert {:ok, %RentPeriod{} = ipc_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: ipc_contract.id,
                 today: today_string
               })

      # Verify IPC factor - should be 1.025 (1 + 0.025)
      assert ipc_period.index_type == :ipc
      assert Decimal.eq?(ipc_period.update_factor, Decimal.new("1.025"))

      # Process ICL job
      assert {:ok, %RentPeriod{} = icl_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: icl_contract.id,
                 today: today_string
               })

      # Verify ICL factor - should be 1.1 (110 / 100)
      assert icl_period.index_type == :icl
      assert Decimal.eq?(icl_period.update_factor, Decimal.new("1.1"))

      # Verify factors are different
      refute Decimal.eq?(ipc_period.update_factor, icl_period.update_factor)
    end
  end

  describe "backdated contract" do
    test "contract starting 2 years ago, verify historical periods created" do
      scope = user_scope_fixture()

      # Fixed dates: July 1st, 2025 as "today"
      today = ~D[2025-07-01]
      # 2 years ago
      contract_start = ~D[2023-07-01]
      # June 30, 2025
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      # Create some historical index data at quarterly intervals
      for i <- 1..6 do
        date = last_month_end |> Date.shift(month: -i * 3) |> Date.beginning_of_month()

        Indexes.create_index_history(%{
          type: :ipc,
          value: Decimal.new("2.5"),
          date: date
        })
      end

      # Create contract starting 2 years ago with 3-month duration
      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(today, month: 12),
            rent_period_duration: 3,
            index_type: :ipc,
            rent: "1000.00"
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.025"),
          today: last_month_end
        )

      # Should have multiple periods already created
      initial_periods = contract.rent_periods
      assert length(initial_periods) >= 4

      # Verify periods cover historical range
      sorted_periods = Enum.sort_by(initial_periods, & &1.start_date, Date)
      first_period = List.first(sorted_periods)

      # First period should start at contract start date
      assert first_period.start_date == contract_start

      # Each period should have index information (except the first)
      periods_with_index = Enum.filter(sorted_periods, &(&1.index_type != nil))
      assert length(periods_with_index) >= 3
    end
  end
end
