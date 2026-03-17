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
          update_factor: Decimal.new("0.03")
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
          update_factor: Decimal.new("0.03")
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
          update_factor: Decimal.new("0.0")
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
          update_factor: Decimal.new("0.03")
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
          update_factor: Decimal.new("0.0")
        )

      Repo.update!(Contract.archive_changeset(contract, scope))

      assert {:ok, :contract_not_found} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 today: today_string
               })
    end
  end
end
