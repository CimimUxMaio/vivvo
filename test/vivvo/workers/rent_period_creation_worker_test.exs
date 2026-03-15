defmodule Vivvo.Workers.RentPeriodCreationWorkerTest do
  use Vivvo.DataCase, async: true

  alias Vivvo.Contracts
  alias Vivvo.Contracts.Contract
  alias Vivvo.Contracts.RentPeriod
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
          index_value: Decimal.new("0.03")
        )

      # Find the period ending this month
      target_period =
        Enum.find(contract.rent_periods, fn p ->
          p.end_date.year == today.year and p.end_date.month == today.month
        end)

      assert target_period != nil

      index_value = Decimal.new("0.05")
      expected_new_start = Date.add(target_period.end_date, 1)
      expected_rent = Decimal.mult(target_period.value, Decimal.add(1, index_value))

      assert {:ok, %RentPeriod{} = rent_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 index_value: index_value,
                 year: today.year,
                 month: today.month
               })

      assert Decimal.eq?(rent_period.value, expected_rent)
      assert rent_period.start_date == expected_new_start
      assert rent_period.index_type == :ipc
      assert Decimal.eq?(rent_period.index_value, index_value)
    end

    test "is idempotent - returns :already_exists when run twice with same year/month" do
      scope = user_scope_fixture()
      today = Date.utc_today()

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
          index_value: Decimal.new("0.03")
        )

      initial_count = length(Contracts.get_contract!(scope, contract.id).rent_periods)

      # First run creates the period
      assert {:ok, %RentPeriod{}} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 index_value: Decimal.new("0.03"),
                 year: today.year,
                 month: today.month
               })

      after_first = length(Contracts.get_contract!(scope, contract.id).rent_periods)
      assert after_first == initial_count + 1

      # Second run with same year/month returns :already_exists
      assert {:ok, :already_exists} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 index_value: Decimal.new("0.03"),
                 year: today.year,
                 month: today.month
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
          index_value: Decimal.new("0.0")
        )

      _target_period =
        Enum.find(contract.rent_periods, fn p ->
          p.end_date.year == today.year and p.end_date.month == today.month
        end)

      assert {:ok, rent_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 index_value: Decimal.new("0.03"),
                 year: today.year,
                 month: today.month
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

      # Try to run with last month's year/month (no period ends then)
      last_month = Date.shift(today, month: -1)

      assert {:ok, :period_not_found} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 index_value: Decimal.new("0.03"),
                 year: last_month.year,
                 month: last_month.month
               })
    end

    test "calculates rent with compound index" do
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
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          index_value: Decimal.new("0.03")
        )

      target_period =
        Enum.find(contract.rent_periods, fn p ->
          p.end_date.year == today.year and p.end_date.month == today.month
        end)

      index_value = Decimal.new("0.03")
      expected_rent = Decimal.mult(target_period.value, Decimal.add(1, index_value))

      assert {:ok, rent_period} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 index_value: index_value,
                 year: today.year,
                 month: today.month
               })

      assert Decimal.eq?(rent_period.value, expected_rent)
    end

    test "returns contract_not_found when contract does not exist" do
      non_existent_id = 99_999_999

      assert {:ok, :contract_not_found} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: non_existent_id,
                 index_value: Decimal.new("0.03"),
                 year: 2025,
                 month: 1
               })
    end

    test "returns contract_not_found when contract is archived" do
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
            end_date: Date.add(today, 400),
            rent_period_duration: 6,
            index_type: :ipc
          },
          past_start_date?: true,
          index_value: Decimal.new("0.0")
        )

      Repo.update!(Contract.archive_changeset(contract, scope))

      assert {:ok, :contract_not_found} =
               perform_job(RentPeriodCreationWorker, %{
                 contract_id: contract.id,
                 index_value: Decimal.new("0.03"),
                 year: today.year,
                 month: today.month
               })
    end
  end
end
