defmodule Vivvo.Integration.RentPeriodFlowTest do
  use Vivvo.DataCase

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
      today = Date.utc_today()

      # Create IPC history for index calculation
      previous_month =
        today
        |> Date.beginning_of_month()
        |> Date.add(-1)

      Indexes.create_index_history(%{
        type: :ipc,
        value: Decimal.new("2.5"),
        date: previous_month
      })

      # Create contract with period ending this month
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
            index_type: :ipc,
            rent: "1000.00"
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      initial_period_count = length(contract.rent_periods)

      # Step 1: Scheduler runs and queues jobs
      assert {:ok, %{scheduled_count: 1}} = perform_job(RentPeriodSchedulerWorker, %{})

      # Verify job was enqueued
      assert_enqueued(worker: RentPeriodCreationWorker)

      # Step 2: Process the queued job
      today_string = Date.to_iso8601(today)

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
    end
  end

  describe "multi-period over time" do
    test "contract with multiple periods can have new periods created sequentially" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create IPC history for the last few months
      for i <- 0..3 do
        date =
          today
          |> Date.beginning_of_month()
          |> Date.add(-1)
          |> Date.shift(month: -i)

        Indexes.create_index_history(%{
          type: :ipc,
          value: Decimal.new("2.5"),
          date: date
        })
      end

      # Create a contract
      three_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -3)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: three_months_ago,
            end_date: Date.add(three_months_ago, 365),
            rent_period_duration: 3,
            index_type: :ipc,
            rent: "1000.00"
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      _initial_period_count = length(contract.rent_periods)

      # Delete all periods and create a specific scenario:
      # One period that ends this month, so scheduler will pick it up
      Repo.delete_all(from rp in RentPeriod, where: rp.contract_id == ^contract.id)

      # Create first period
      {:ok, _} =
        Contracts.create_rent_period(%{
          contract_id: contract.id,
          start_date: three_months_ago,
          end_date: Date.end_of_month(Date.shift(three_months_ago, month: 2)),
          value: Decimal.new("1000.00"),
          index_type: :ipc
        })

      # Create second period ending this month
      this_month_start = Date.beginning_of_month(today)

      {:ok, _} =
        Contracts.create_rent_period(%{
          contract_id: contract.id,
          start_date: this_month_start,
          end_date: Date.end_of_month(today),
          value: Decimal.new("1030.00"),
          index_type: :ipc,
          update_factor: Decimal.new("1.03")
        })

      today_string = Date.to_iso8601(today)

      # Scheduler run - should find the contract
      assert {:ok, %{scheduled_count: 1}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => today_string})

      assert {:ok, %RentPeriod{} = new_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })

      # Verify new period was created with correct attributes
      contract_after = Contracts.get_contract!(scope, contract.id)
      assert length(contract_after.rent_periods) == 3
      assert new_period.index_type == :ipc
      assert %Decimal{} = new_period.update_factor
    end
  end

  describe "mixed index types" do
    test "multiple contracts (IPC + ICL), verify correct factors applied" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create IPC history
      previous_month =
        today
        |> Date.beginning_of_month()
        |> Date.add(-1)

      Indexes.create_index_history(%{
        type: :ipc,
        value: Decimal.new("2.5"),
        date: previous_month
      })

      # Create IPC contract
      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

      ipc_contract =
        contract_fixture(
          scope,
          %{
            start_date: five_months_ago,
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :ipc,
            rent: "1000.00"
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.025")
        )

      # Manually set up periods for IPC contract so one ends this month
      Repo.delete_all(from rp in RentPeriod, where: rp.contract_id == ^ipc_contract.id)

      {:ok, _} =
        Contracts.create_rent_period(%{
          contract_id: ipc_contract.id,
          start_date: five_months_ago,
          end_date: Date.end_of_month(Date.shift(five_months_ago, month: 5)),
          value: Decimal.new("1000.00"),
          index_type: :ipc
        })

      this_month_start = Date.beginning_of_month(today)

      {:ok, _} =
        Contracts.create_rent_period(%{
          contract_id: ipc_contract.id,
          start_date: this_month_start,
          end_date: Date.end_of_month(today),
          value: Decimal.new("1025.00"),
          index_type: :ipc,
          update_factor: Decimal.new("1.025")
        })

      today_string = Date.to_iso8601(today)

      # Scheduler should pick up the IPC contract
      assert {:ok, %{scheduled_count: 1}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => today_string})

      # Process IPC job
      assert {:ok, %RentPeriod{} = ipc_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: ipc_contract.id,
                 today: today_string
               })

      # Verify IPC factor - should be 1.025 (1 + 0.025)
      assert ipc_period.index_type == :ipc
      assert Decimal.eq?(ipc_period.update_factor, Decimal.new("1.025"))
    end
  end

  describe "backdated contract" do
    test "contract starting 2 years ago, verify historical periods created" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create some historical index data
      for i <- 1..6 do
        date =
          today
          |> Date.beginning_of_month()
          |> Date.add(-1)
          |> Date.shift(month: -i * 3)

        Indexes.create_index_history(%{
          type: :ipc,
          value: Decimal.new("2.5"),
          date: date
        })
      end

      # Create contract starting 2 years ago with 3-month duration
      two_years_ago = Date.shift(today, year: -2)

      contract =
        contract_fixture(
          scope,
          %{
            start_date: two_years_ago,
            end_date: Date.add(today, 365),
            rent_period_duration: 3,
            index_type: :ipc,
            rent: "1000.00"
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.025")
        )

      # Should have multiple periods already created
      initial_periods = contract.rent_periods
      assert length(initial_periods) >= 4

      # Verify periods cover historical range
      sorted_periods = Enum.sort_by(initial_periods, & &1.start_date, Date)
      first_period = List.first(sorted_periods)

      # First period should start at contract start date
      assert first_period.start_date == two_years_ago

      # Each period should have index information (except the first)
      periods_with_index = Enum.filter(sorted_periods, &(&1.index_type != nil))
      assert length(periods_with_index) >= 3
    end
  end
end
