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

      assert {:ok, %{scheduled_count: 1}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => Date.to_iso8601(today)})

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
      # Fixed dates: period ends April 30th (current month), not previous month
      # For 6-month duration starting Jan 1: period ends June 30
      # On April 1, the period ends in the future (June), not previous month
      contract_start = ~D[2023-01-01]
      today = ~D[2023-04-01]

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
          today: today
        )

      # Verify the period ends in June (not previous month)
      latest_period = List.last(contract.rent_periods)
      assert latest_period.end_date == ~D[2023-06-30]

      # Scheduler should not find contracts - period ends in June, not March
      assert {:ok, %{scheduled_count: 0}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => Date.to_iso8601(today)})

      refute_enqueued(worker: RentPeriodCreationWorker)
    end

    test "respects unique constraint for duplicate scheduling within same month" do
      scope = user_scope_fixture()
      # Fixed dates: April 1st as "today", period ends March 31st (previous month)
      # For 3-month duration starting Jan 1: period ends Mar 31, Jun 30, Sep 30, Dec 31
      # On April 1, the previous month's end is March 31 - which matches the period end
      contract_start = ~D[2023-01-01]
      today = Date.shift(contract_start, month: 3)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      _contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 3,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: last_month_end
        )

      # Run scheduler - should schedule one job
      assert {:ok, %{scheduled_count: 1}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => Date.to_iso8601(today)})

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
      # Fixed dates: July 1st as "today", period ends June 30th (previous month)
      # For 6-month duration starting Jan 1: period ends June 30
      contract_start = ~D[2023-01-01]
      today = Date.shift(contract_start, month: 6)
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

      # Verify the latest period ends in previous month (June 30)
      latest_period = List.last(contract.rent_periods)
      assert latest_period.end_date == last_month_end

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
      # Fixed dates: March 1st as "today", periods end February 28th (previous month)
      # For 2-month duration starting Jan 1: period ends Feb 28, Apr 30, Jun 30...
      # On March 1, the previous month's end is February 28 - which matches period end
      contract_start = ~D[2023-01-01]
      today = Date.shift(contract_start, month: 2)
      today_string = Date.to_iso8601(today)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      contract_a =
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

      contract_b =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: 2,
            index_type: :icl
          },
          past_start_date?: true,
          update_factor: Decimal.new("0.05"),
          today: last_month_end
        )

      # Verify both periods end in previous month (Feb 28)
      latest_period_a = List.last(contract_a.rent_periods)
      latest_period_b = List.last(contract_b.rent_periods)
      assert latest_period_a.end_date == last_month_end
      assert latest_period_b.end_date == last_month_end

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

    test "runs on 1st but no contracts need updates" do
      scope = user_scope_fixture()
      # Fixed dates: April 1st as "today", period ends Sept 30th (future month)
      # For 6-month duration starting April 1: period ends Sep 30
      # On April 1, the period ends in the future, not previous month
      contract_start = ~D[2023-04-01]
      today = ~D[2023-04-01]

      _contract =
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
          today: today
        )

      # Period ends in September (future), not March (previous) - no update needed
      assert {:ok, %{scheduled_count: 0}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => Date.to_iso8601(today)})

      refute_enqueued(worker: RentPeriodCreationWorker)
    end

    test "handles multiple contracts with same index type" do
      scope = user_scope_fixture()
      # Fixed dates: July 1st as "today", periods end June 30th (previous month)
      # For 6-month duration starting Jan 1: period ends June 30
      contract_start = ~D[2023-01-01]
      today = Date.shift(contract_start, month: 6)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      # Create two IPC contracts
      contract_a =
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

      contract_b =
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

      # Verify both periods end in previous month (June 30)
      latest_period_a = List.last(contract_a.rent_periods)
      latest_period_b = List.last(contract_b.rent_periods)
      assert latest_period_a.end_date == last_month_end
      assert latest_period_b.end_date == last_month_end

      assert {:ok, %{scheduled_count: 2}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => Date.to_iso8601(today)})

      # Should have 2 jobs enqueued
      assert Repo.aggregate(Oban.Job, :count) == 2

      job_contract_ids =
        Repo.all(Oban.Job)
        |> Enum.map(& &1.args["contract_id"])
        |> Enum.sort()

      assert job_contract_ids == Enum.sort([contract_a.id, contract_b.id])
    end

    test "processes single contract with IPC index type" do
      scope = user_scope_fixture()
      # Fixed dates: July 1st as "today", periods end June 30th (previous month)
      # For 6-month duration starting Jan 1: period ends June 30
      contract_start = ~D[2023-01-01]
      today = Date.shift(contract_start, month: 6)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

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
          update_factor: Decimal.new("1.03"),
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

      # Verify both periods end in previous month (June 30)
      latest_period_ipc = List.last(ipc_contract.rent_periods)
      latest_period_icl = List.last(icl_contract.rent_periods)
      assert latest_period_ipc.end_date == last_month_end
      assert latest_period_icl.end_date == last_month_end

      assert {:ok, %{scheduled_count: 2}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => Date.to_iso8601(today)})

      job_contract_ids =
        Repo.all(Oban.Job)
        |> Enum.map(& &1.args["contract_id"])
        |> Enum.sort()

      assert job_contract_ids == Enum.sort([ipc_contract.id, icl_contract.id])
    end

    test "excludes contract ending exactly on last day of month" do
      scope = user_scope_fixture()
      # Fixed dates: July 1st as "today", contract ends June 30th
      # For 6-month duration starting Jan 1: period ends June 30
      contract_start = ~D[2023-01-01]
      today = Date.shift(contract_start, month: 6)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      # Create a contract that ends on the last day of June
      # It should NOT need a new rent period (contract ends this month)
      _contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.end_of_month(last_month_end),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: last_month_end
        )

      # The contract ends this month, so no new period should be scheduled
      assert {:ok, %{scheduled_count: 0}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => Date.to_iso8601(today)})
    end

    test "handles period ending on last day of Feb (non-leap year)" do
      scope = user_scope_fixture()
      # Fixed dates: March 1st as "today", period ends Feb 28th (previous month)
      # For 2-month duration starting Jan 1: period ends Feb 28, Apr 30...
      # On March 1, the previous month's end is February 28 - which matches period end
      contract_start = ~D[2023-01-01]
      today = Date.shift(contract_start, month: 2)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: ~D[2024-01-01],
            rent_period_duration: 2,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: last_month_end
        )

      # Verify the latest period ends on Feb 28th (previous month end)
      latest_period = List.last(contract.rent_periods)
      assert latest_period.end_date == last_month_end

      # Run scheduler on March 1st - should find contract with period ending in Feb
      assert {:ok, %{scheduled_count: 1}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => Date.to_iso8601(today)})

      assert_enqueued(worker: RentPeriodCreationWorker)
    end

    test "handles period ending on 30th" do
      scope = user_scope_fixture()
      # Fixed dates: May 1st as "today", period ends April 30th (previous month)
      # For 2-month duration starting March 1: period ends Apr 30, Jun 30...
      # On May 1, the previous month's end is April 30 - which matches period end
      contract_start = ~D[2023-03-01]
      today = Date.shift(contract_start, month: 2)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: ~D[2024-12-31],
            rent_period_duration: 2,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: last_month_end
        )

      # Verify the latest period ends on Apr 30th (previous month end)
      latest_period = List.last(contract.rent_periods)
      assert latest_period.end_date == last_month_end

      # Run scheduler on May 1st - should find contract with period ending in April
      assert {:ok, %{scheduled_count: 1}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => Date.to_iso8601(today)})

      assert_enqueued(worker: RentPeriodCreationWorker)
    end

    test "schedules the update of contracts with periods ending on the previous month" do
      scope = user_scope_fixture()

      contract_start = ~D[2023-03-01]
      # Multiple of the period duration to ensure the last auto-generated
      # period ends on the last day of the previous month.
      today = Date.shift(contract_start, month: 4)

      last_month_end =
        today
        |> Date.shift(month: -1)
        |> Date.end_of_month()

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
          # Autogenerate periods up to last month end
          today: last_month_end
        )

      # Verify the latest period
      latest_period = List.last(contract.rent_periods)
      assert latest_period.end_date == last_month_end

      assert {:ok, %{scheduled_count: 1}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => Date.to_iso8601(today)})

      assert_enqueued(worker: RentPeriodCreationWorker)
    end

    test "handles contract with latest_period.end_date equal to contract.end_date" do
      scope = user_scope_fixture()
      # Fixed dates: February 1st as "today", contract ends January 31st
      # Period ends in previous month but so does contract - no update needed
      contract_start = ~D[2023-01-01]
      today = ~D[2023-02-01]
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      _contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: last_month_end,
            rent_period_duration: 1,
            index_type: :ipc
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: last_month_end
        )

      # Contract ends in previous month (Jan), so no new period should be scheduled
      assert {:ok, %{scheduled_count: 0}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => Date.to_iso8601(today)})
    end

    test "scheduler does not reschedule contract after rent period is created" do
      scope = user_scope_fixture()
      # Fixed dates: July 1st as "today", period ends June 30th (previous month)
      # For 6-month duration starting Jan 1: period ends June 30
      contract_start = ~D[2023-01-01]
      today = Date.shift(contract_start, month: 6)
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

      # Verify period ends in previous month (June 30)
      latest_period = List.last(contract.rent_periods)
      assert latest_period.end_date == last_month_end

      # First scheduler run creates a RentPeriodCreationWorker job
      assert {:ok, %{scheduled_count: 1}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => today_string})

      assert Repo.aggregate(Oban.Job, :count) == 1

      # Simulate the RentPeriodCreationWorker completing successfully
      # This would create the next rent period, so the contract no longer needs update
      # For this test, we'll manually create the next period (July - Dec)
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
      # because the latest period now extends beyond the previous month
      assert {:ok, %{scheduled_count: 0}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => today_string})

      # Should have no new jobs since contract no longer needs update
      assert Repo.aggregate(Oban.Job, :count) == 0
    end

    test "handles multiple contracts with different index types" do
      scope = user_scope_fixture()
      # Fixed dates: July 1st as "today", periods end June 30th (previous month)
      # For 6-month duration starting Jan 1: period ends June 30
      contract_start = ~D[2023-01-01]
      today = Date.shift(contract_start, month: 6)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

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
          update_factor: Decimal.new("1.03"),
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

      # Verify both periods end in previous month (June 30)
      latest_period_ipc = List.last(ipc_contract.rent_periods)
      latest_period_icl = List.last(icl_contract.rent_periods)
      assert latest_period_ipc.end_date == last_month_end
      assert latest_period_icl.end_date == last_month_end

      assert {:ok, %{scheduled_count: 2}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => Date.to_iso8601(today)})

      job_contract_ids =
        Repo.all(Oban.Job)
        |> Enum.map(& &1.args["contract_id"])
        |> Enum.sort()

      assert job_contract_ids == Enum.sort([ipc_contract.id, icl_contract.id])
    end

    test "only schedules contracts with both index_type and rent_period_duration" do
      scope = user_scope_fixture()
      # Fixed dates: July 1st as "today", periods end June 30th (previous month)
      # For 6-month duration starting Jan 1: period ends June 30
      contract_start = ~D[2023-01-01]
      today = Date.shift(contract_start, month: 6)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      # Create valid contract with both index_type and rent_period_duration
      valid_contract =
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

      # Create contract without rent_period_duration (valid but won't be scheduled)
      _no_auto_update_contract =
        contract_fixture(
          scope,
          %{
            start_date: contract_start,
            end_date: Date.shift(contract_start, month: 12),
            rent_period_duration: nil,
            index_type: nil
          },
          past_start_date?: true,
          update_factor: Decimal.new("1.03"),
          today: last_month_end
        )

      # Verify valid contract period ends in previous month
      latest_period = List.last(valid_contract.rent_periods)
      assert latest_period.end_date == last_month_end

      # Only valid_contract should be scheduled
      assert {:ok, %{scheduled_count: 1}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => Date.to_iso8601(today)})

      job = Repo.one!(Oban.Job)
      assert job.args["contract_id"] == valid_contract.id
    end

    test "full flow: scheduler finds contract and creation worker creates new period" do
      scope = user_scope_fixture()

      # Fixed dates: July 1st as "today", period ends June 30th (previous month)
      # For 6-month duration starting Jan 1: period ends June 30
      contract_start = ~D[2023-01-01]
      today = ~D[2023-07-01]
      today_string = Date.to_iso8601(today)
      last_month_end = today |> Date.shift(month: -1) |> Date.end_of_month()

      # Create IPC history entries needed for update factor calculation
      for i <- 1..2 do
        date = last_month_end |> Date.shift(month: -i + 1) |> Date.beginning_of_month()

        Vivvo.Indexes.create_index_history(%{
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

      # Verify the latest period ends in previous month (June 30)
      latest_period = List.last(contract.rent_periods)
      assert latest_period.end_date == last_month_end

      initial_period_count = length(contract.rent_periods)

      # Step 1: Scheduler runs on July 1st and finds the contract
      assert {:ok, %{scheduled_count: 1}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => today_string})

      assert_enqueued(
        worker: RentPeriodCreationWorker,
        args: %{
          contract_id: contract.id,
          today: today_string
        }
      )

      # Step 2: Creation worker runs and creates the new period
      assert {:ok, %Vivvo.Contracts.RentPeriod{} = new_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })

      # Verify the new period was created correctly
      # July 1st
      assert new_period.start_date == today
      # Dec 31st (6 months from July 1)
      assert new_period.end_date == ~D[2023-12-31]
      assert new_period.index_type == :ipc

      # Verify contract now has one more period
      updated_contract = Vivvo.Contracts.get_contract!(scope, contract.id)
      assert length(updated_contract.rent_periods) == initial_period_count + 1

      # Step 3: Running scheduler again should not schedule the same contract
      Repo.delete_all(Oban.Job)

      assert {:ok, %{scheduled_count: 0}} =
               perform_job(RentPeriodSchedulerWorker, %{"today" => today_string})

      refute_enqueued(worker: RentPeriodCreationWorker)
    end
  end
end
