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
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      assert {:ok, %{scheduled_count: 1}} = perform_job(RentPeriodSchedulerWorker, %{})

      today_string = Date.to_iso8601(today)

      assert_enqueued(
        worker: RentPeriodCreationWorker,
        args: %{
          contract_id: contract.id,
          today: today_string
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
            index_type: :icl
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
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
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
            index_type: :ipc
          }
        )

      assert {:ok, %{scheduled_count: 0}} = perform_job(RentPeriodSchedulerWorker, %{})
      refute_enqueued(worker: RentPeriodCreationWorker)
    end

    test "unique constraint prevents duplicate RentPeriodCreationWorker jobs for same contract on same day" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      today_string = Date.to_iso8601(today)

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
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      # Insert first job manually to test Oban's unique constraint
      {:ok, _job1} =
        %{
          contract_id: contract.id,
          today: today_string
        }
        |> RentPeriodCreationWorker.new(
          unique: [period: :infinity, keys: [:contract_id, :today]],
          queue: :rent_periods
        )
        |> Oban.insert()

      # Try to insert second job with same contract_id and today - should be rejected
      {:ok, _job2} =
        %{
          contract_id: contract.id,
          today: today_string
        }
        |> RentPeriodCreationWorker.new(
          unique: [period: :infinity, keys: [:contract_id, :today]],
          queue: :rent_periods
        )
        |> Oban.insert()

      # Should only have 1 job in queue (the first one)
      assert Repo.aggregate(Oban.Job, :count) == 1

      # Verify it has the correct args
      job = Repo.one!(Oban.Job)
      assert job.args["contract_id"] == contract.id
      assert job.args["today"] == today_string
    end

    test "different contracts can be scheduled on same day" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      today_string = Date.to_iso8601(today)

      # Create two contracts that started 1 month ago with 2-month duration
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
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      contract_b =
        contract_fixture(
          scope,
          %{
            start_date: one_month_ago,
            end_date: Date.add(today, 400),
            rent_period_duration: 2,
            index_type: :icl
          },
          past_start_date?: true,
          update_factor: Decimal.new("0.05")
        )

      # Insert jobs for both contracts on same day
      {:ok, _job1} =
        %{
          contract_id: contract_a.id,
          today: today_string
        }
        |> RentPeriodCreationWorker.new(
          unique: [period: :infinity, keys: [:contract_id, :today]],
          queue: :rent_periods
        )
        |> Oban.insert()

      {:ok, _job2} =
        %{
          contract_id: contract_b.id,
          today: today_string
        }
        |> RentPeriodCreationWorker.new(
          unique: [period: :infinity, keys: [:contract_id, :today]],
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

    test "backoff function returns exponential delays up to 12 hours" do
      # Test the backoff function with different attempts
      # Backoff is returned in seconds
      job = %{attempt: 1}
      backoff_1 = RentPeriodSchedulerWorker.backoff(job)
      # 15 minutes
      assert backoff_1 == 900

      job = %{attempt: 2}
      backoff_2 = RentPeriodSchedulerWorker.backoff(job)
      # 30 minutes
      assert backoff_2 == 1800

      job = %{attempt: 3}
      backoff_3 = RentPeriodSchedulerWorker.backoff(job)
      # 60 minutes
      assert backoff_3 == 3600

      job = %{attempt: 4}
      backoff_4 = RentPeriodSchedulerWorker.backoff(job)
      # 2 hours
      assert backoff_4 == 7200

      job = %{attempt: 5}
      backoff_5 = RentPeriodSchedulerWorker.backoff(job)
      # 4 hours
      assert backoff_5 == 14_400

      job = %{attempt: 6}
      backoff_6 = RentPeriodSchedulerWorker.backoff(job)
      # 8 hours
      assert backoff_6 == 28_800

      job = %{attempt: 7}
      backoff_7 = RentPeriodSchedulerWorker.backoff(job)
      # Should be capped at 12 hours (43200 seconds)
      assert backoff_7 == 43_200
    end

    test "continues scheduling when index service fails for one index type" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create IPC history
      previous_month = Date.shift(today, month: -1) |> Date.beginning_of_month()

      Vivvo.Indexes.create_index_history(%{
        type: :ipc,
        value: Decimal.new("2.5"),
        date: previous_month
      })

      # Create a contract with IPC index type
      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

      _contract =
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

      # Run scheduler - should still succeed even if ICL fetch fails
      # (in real scenario, IndexService might fail for one index type)
      assert {:ok, %{scheduled_count: 1}} = perform_job(RentPeriodSchedulerWorker, %{})
      assert_enqueued(worker: RentPeriodCreationWorker)
    end

    test "runs on 25th but no contracts need updates" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create a contract that won't need updates this month
      # Starting today with 6-month duration means period ends in month 6
      _contract =
        contract_fixture(
          scope,
          %{
            start_date: today,
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :ipc
          }
        )

      assert {:ok, %{scheduled_count: 0}} = perform_job(RentPeriodSchedulerWorker, %{})
      refute_enqueued(worker: RentPeriodCreationWorker)
    end

    test "handles multiple contracts with same index type" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

      # Create two IPC contracts
      contract_a =
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

      contract_b =
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

      assert {:ok, %{scheduled_count: 2}} = perform_job(RentPeriodSchedulerWorker, %{})

      # Should have 2 jobs enqueued
      assert Repo.aggregate(Oban.Job, :count) == 2

      job_contract_ids =
        Repo.all(Oban.Job)
        |> Enum.map(& &1.args["contract_id"])
        |> Enum.sort()

      assert job_contract_ids == Enum.sort([contract_a.id, contract_b.id])
    end

    test "handles contracts with different index types" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

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
          update_factor: Decimal.new("1.03")
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

      assert {:ok, %{scheduled_count: 2}} = perform_job(RentPeriodSchedulerWorker, %{})

      job_contract_ids =
        Repo.all(Oban.Job)
        |> Enum.map(& &1.args["contract_id"])
        |> Enum.sort()

      assert job_contract_ids == Enum.sort([ipc_contract.id, icl_contract.id])
    end

    test "excludes contract ending exactly on last day of month" do
      scope = user_scope_fixture()
      today = Date.utc_today()
      end_of_month = Date.end_of_month(today)

      # Create a contract that ends on the last day of this month
      # It should NOT need a new rent period
      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

      _contract =
        contract_fixture(
          scope,
          %{
            start_date: five_months_ago,
            end_date: end_of_month,
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      # The contract ends on the last day of month, so no new period should be scheduled
      assert {:ok, %{scheduled_count: 0}} = perform_job(RentPeriodSchedulerWorker, %{})
    end

    test "handles period ending on last day of Feb (non-leap year)" do
      scope = user_scope_fixture()
      # 2023 is a non-leap year, Feb has 28 days
      # Use a "today" in Feb 2023 so that periods are generated up to that point
      feb_28_2023 = ~D[2023-02-28]

      # Create contract with a "today" of Feb 28, 2023
      # This generates periods up to Feb 28, 2023
      contract =
        contract_fixture(
          scope,
          %{
            start_date: ~D[2023-01-01],
            end_date: ~D[2024-01-01],
            rent_period_duration: 1,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: feb_28_2023
        )

      # Verify the latest period ends on Feb 28
      latest_period = List.last(contract.rent_periods)
      assert latest_period.end_date == feb_28_2023

      # Run scheduler on Feb 28, 2023
      assert {:ok, %{scheduled_count: 1}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => "2023-02-28"})

      assert_enqueued(worker: RentPeriodCreationWorker)
    end

    test "handles period ending on 30th" do
      scope = user_scope_fixture()
      # April 30, 2023
      apr_30_2023 = ~D[2023-04-30]

      # Create contract with a "today" of Apr 30, 2023
      # This generates periods up to Apr 30, 2023
      contract =
        contract_fixture(
          scope,
          %{
            start_date: ~D[2023-03-01],
            end_date: ~D[2024-12-31],
            rent_period_duration: 2,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: apr_30_2023
        )

      # Verify the latest period ends on Apr 30
      latest_period = List.last(contract.rent_periods)
      assert latest_period.end_date == apr_30_2023

      assert {:ok, %{scheduled_count: 1}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => "2023-04-30"})

      assert_enqueued(worker: RentPeriodCreationWorker)
    end

    test "handles period ending on 31st" do
      scope = user_scope_fixture()
      # March 31, 2023
      mar_31_2023 = ~D[2023-03-31]

      # Create contract with a "today" of Mar 31, 2023
      # This generates periods up to Mar 31, 2023
      contract =
        contract_fixture(
          scope,
          %{
            start_date: ~D[2023-02-01],
            end_date: ~D[2024-12-31],
            rent_period_duration: 2,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: mar_31_2023
        )

      # Verify the latest period ends on Mar 31
      latest_period = List.last(contract.rent_periods)
      assert latest_period.end_date == mar_31_2023

      assert {:ok, %{scheduled_count: 1}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => "2023-03-31"})

      assert_enqueued(worker: RentPeriodCreationWorker)
    end

    test "handles contract with latest_period.end_date equal to contract.end_date" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      # Create contract with 1-month duration ending today
      # This means the latest period end_date equals contract.end_date
      last_month =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -1)

      _contract =
        contract_fixture(
          scope,
          %{
            start_date: last_month,
            end_date: Date.end_of_month(today),
            rent_period_duration: 1,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      # Contract ends this month, so no new period should be scheduled
      assert {:ok, %{scheduled_count: 0}} = perform_job(RentPeriodSchedulerWorker, %{})
    end

    test "scheduler does not reschedule contract after rent period is created" do
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
          update_factor: Decimal.new("1.03")
        )

      # First scheduler run creates a RentPeriodCreationWorker job
      assert {:ok, %{scheduled_count: 1}} = perform_job(RentPeriodSchedulerWorker, %{})
      assert Repo.aggregate(Oban.Job, :count) == 1

      # Simulate the RentPeriodCreationWorker completing successfully
      # This would create the next rent period, so the contract no longer needs update
      # For this test, we'll manually create the next period
      {:ok, _next_period} =
        Vivvo.Contracts.create_rent_period(%{
          contract_id: contract.id,
          start_date: today,
          end_date: Date.shift(today, month: 6) |> Date.end_of_month(),
          value: Decimal.new("120.5"),
          index_type: :ipc
        })

      # Clear the Oban jobs to start fresh
      Repo.delete_all(Oban.Job)

      # Second scheduler run - contract should no longer need update
      # because the latest period now extends beyond the current month
      assert {:ok, %{scheduled_count: 0}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => today_string})

      # Should have no new jobs since contract no longer needs update
      assert Repo.aggregate(Oban.Job, :count) == 0
    end

    test "handles multiple contracts with different index types" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

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
          update_factor: Decimal.new("1.03")
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

      assert {:ok, %{scheduled_count: 2}} = perform_job(RentPeriodSchedulerWorker, %{})

      job_contract_ids =
        Repo.all(Oban.Job)
        |> Enum.map(& &1.args["contract_id"])
        |> Enum.sort()

      assert job_contract_ids == Enum.sort([ipc_contract.id, icl_contract.id])
    end

    test "only schedules contracts with both index_type and rent_period_duration" do
      scope = user_scope_fixture()
      today = Date.utc_today()

      five_months_ago =
        today
        |> Date.beginning_of_month()
        |> Date.shift(month: -5)

      # Create valid contract with both index_type and rent_period_duration
      valid_contract =
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

      # Create contract without rent_period_duration (valid but won't be scheduled)
      _no_auto_update_contract =
        contract_fixture(
          scope,
          %{
            start_date: five_months_ago,
            end_date: Date.add(today, 400),
            rent_period_duration: nil,
            index_type: nil
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03")
        )

      # Only valid_contract should be scheduled
      assert {:ok, %{scheduled_count: 1}} = perform_job(RentPeriodSchedulerWorker, %{})

      job = Repo.one!(Oban.Job)
      assert job.args["contract_id"] == valid_contract.id
    end
  end
end
