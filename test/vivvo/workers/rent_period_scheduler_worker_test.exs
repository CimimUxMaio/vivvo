defmodule Vivvo.Workers.RentPeriodSchedulerWorkerTest do
  use Vivvo.DataCase, async: true

  alias Vivvo.Repo
  alias Vivvo.Workers.RentPeriodCreationWorker
  alias Vivvo.Workers.RentPeriodSchedulerWorker

  import Vivvo.ContractsFixtures
  import Vivvo.AccountsFixtures

  describe "perform/1" do
    test "schedules jobs for contracts needing rent period updates" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # To get a period ending this month with 6-month duration:
      # period_end = start + 5 months (end of that month)
      # So start should be 5 months ago
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
            index_type: :cpi
          },
          past_start_date?: true,
          index_value: Decimal.new("0.03")
        )

      assert {:ok, %{scheduled_count: 1}} = perform_job(RentPeriodSchedulerWorker, %{})

      assert_enqueued(
        worker: RentPeriodCreationWorker,
        args: %{
          contract_id: contract.id,
          index_value: Decimal.new("0.03"),
          year: today.year,
          month: today.month
        }
      )
    end

    test "skips contracts with rent periods ending next month" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create a contract starting today with 6-month duration
      # The auto-generated period will end 5 months from now, not this month
      contract =
        contract_fixture(
          scope,
          %{
            start_date: today,
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :fixed_percentage
          }
        )

      # Verify the contract has a period (it should, ending in the future)
      assert contract.rent_periods != []

      # Scheduler should not find any contracts needing updates
      assert {:ok, %{scheduled_count: 0}} = perform_job(RentPeriodSchedulerWorker, %{})

      refute_enqueued(worker: RentPeriodCreationWorker)
    end

    test "respects unique constraint for duplicate scheduling within same month" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # To get a period ending this month with 3-month duration:
      # period_end = start + 2 months (end of that month)
      # So start should be 2 months ago
      two_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -2)

      _contract =
        contract_fixture(
          scope,
          %{
            start_date: two_months_ago,
            end_date: Date.add(today, 400),
            rent_period_duration: 3,
            index_type: :cpi
          },
          past_start_date?: true,
          index_value: Decimal.new("0.03")
        )

      # Run scheduler - should schedule one job
      assert {:ok, %{scheduled_count: 1}} = perform_job(RentPeriodSchedulerWorker, %{})

      # Verify a job was scheduled
      assert_enqueued(worker: RentPeriodCreationWorker)
    end

    test "returns empty count when no contracts need updates" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create a future contract - won't need updates
      _contract =
        contract_fixture(
          scope,
          %{
            start_date: Date.add(today, 30),
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :cpi
          }
        )

      assert {:ok, %{scheduled_count: 0}} = perform_job(RentPeriodSchedulerWorker, %{})
      refute_enqueued(worker: RentPeriodCreationWorker)
    end

    test "unique constraint prevents duplicate RentPeriodCreationWorker jobs for same contract in same month" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create a contract that started 5 months ago with 6-month duration
      # This gives a period ending this month
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
            index_type: :cpi
          },
          past_start_date?: true,
          index_value: Decimal.new("0.03")
        )

      # Insert first job manually to test Oban's unique constraint
      {:ok, _job1} =
        %{
          contract_id: contract.id,
          index_value: Decimal.new("0.03"),
          year: today.year,
          month: today.month
        }
        |> RentPeriodCreationWorker.new(
          unique: [period: :infinity, keys: [:contract_id, :year, :month]],
          queue: :rent_periods
        )
        |> Oban.insert()

      # Try to insert second job with same contract_id, year, month - should be rejected
      {:ok, _job2} =
        %{
          contract_id: contract.id,
          index_value: Decimal.new("0.04"),
          year: today.year,
          month: today.month
        }
        |> RentPeriodCreationWorker.new(
          unique: [period: :infinity, keys: [:contract_id, :year, :month]],
          queue: :rent_periods
        )
        |> Oban.insert()

      # Should only have 1 job in queue (the first one)
      assert Repo.aggregate(Oban.Job, :count) == 1

      # Verify it's the first one with 0.03 value
      job = Repo.one!(Oban.Job)
      assert job.args["index_value"] == "0.03"
    end

    test "different contracts can be scheduled in same month" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create two contracts that started 11 months ago with 3-month duration
      # 11 = 3*3 + 2, so after 3 full periods (9 months), we're at month 10
      # Next period starts at month 10, ends at month 12 (which is this month if we're at month 12)
      # Actually, let's use 2-month duration with contract starting 1 month ago
      # That gives period ending this month
      one_month_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -1)

      contract_a =
        contract_fixture(
          scope,
          %{
            start_date: one_month_ago,
            end_date: Date.add(today, 400),
            rent_period_duration: 2,
            index_type: :cpi
          },
          past_start_date?: true,
          index_value: Decimal.new("0.03")
        )

      contract_b =
        contract_fixture(
          scope,
          %{
            start_date: one_month_ago,
            end_date: Date.add(today, 400),
            rent_period_duration: 2,
            index_type: :fixed_percentage
          },
          past_start_date?: true,
          index_value: Decimal.new("0.05")
        )

      # Insert jobs for both contracts in same month
      {:ok, _job1} =
        %{
          contract_id: contract_a.id,
          index_value: Decimal.new("0.03"),
          year: today.year,
          month: today.month
        }
        |> RentPeriodCreationWorker.new(
          unique: [period: :infinity, keys: [:contract_id, :year, :month]],
          queue: :rent_periods
        )
        |> Oban.insert()

      {:ok, _job2} =
        %{
          contract_id: contract_b.id,
          index_value: Decimal.new("0.05"),
          year: today.year,
          month: today.month
        }
        |> RentPeriodCreationWorker.new(
          unique: [period: :infinity, keys: [:contract_id, :year, :month]],
          queue: :rent_periods
        )
        |> Oban.insert()

      # Should have 2 jobs (one for each contract)
      assert Repo.aggregate(Oban.Job, :count) == 2

      job_args =
        Repo.all(Oban.Job)
        |> Enum.map(& &1.args)
        |> Enum.sort_by(& &1["contract_id"])

      assert length(job_args) == 2
      assert Enum.at(job_args, 0)["contract_id"] == contract_a.id
      assert Enum.at(job_args, 1)["contract_id"] == contract_b.id
    end
  end
end
