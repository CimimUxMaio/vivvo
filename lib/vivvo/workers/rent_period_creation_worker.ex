defmodule Vivvo.Workers.RentPeriodCreationWorker do
  @moduledoc """
  Worker that creates a new rent period for a specific contract.

  Computes the update factor based on the contract's index type:
  - IPC: Accumulates historic rates between last update and previous month
  - ICL: Calculates ratio between latest value and value at last update date

  Performs idempotency checks to prevent duplicate rent periods.

  The worker uses the scheduler's year and month to identify which period
  ended in that month, then creates the next period. This ensures true
  idempotency - running the same job twice with the same year/month will
  not create duplicate periods.

  Date calculations follow the same pattern as Contracts.create_contract:
  - Start date: previous_period.end_date + 1 day
  - End date: min(start_date + (duration - 1) months, end_of_month, contract.end_date)
  """

  use Oban.Worker, queue: :rent_periods, max_attempts: 3

  alias Vivvo.Contracts
  alias Vivvo.Indexes

  require Logger

  @impl Oban.Worker
  def perform(%{
        args: %{
          "contract_id" => contract_id,
          "today" => today_string
        }
      }) do
    today = Date.from_iso8601!(today_string)

    case Contracts.get_system_contract(contract_id) do
      nil ->
        Logger.warning("RentPeriodCreationWorker: Contract #{contract_id} not found, skipping")
        {:ok, :contract_not_found}

      contract ->
        create_rent_period_for_contract(contract, today)
    end
  end

  defp create_rent_period_for_contract(contract, today) do
    # Calculate the previous month (the one that just ended)
    # by subtracting today.day days from today to get the last day of previous month
    previous_month_date = Date.add(today, -today.day)
    year = previous_month_date.year
    month = previous_month_date.month

    # Find the period ending in the previous month
    target_period =
      Enum.find(contract.rent_periods, fn period ->
        period.end_date.year == year and period.end_date.month == month
      end)

    case target_period do
      nil ->
        Logger.warning(
          "RentPeriodCreationWorker: No period ending in #{year}-#{month} found for contract #{contract.id}"
        )

        {:ok, :period_not_found}

      period ->
        new_start_date = Date.add(period.end_date, 1)

        if period_already_exists?(contract.rent_periods, new_start_date) do
          Logger.info(
            "RentPeriodCreationWorker: Period already exists at #{new_start_date} for contract #{contract.id}, skipping"
          )

          {:ok, :already_exists}
        else
          new_end_date =
            Contracts.period_end_date(
              contract.rent_period_duration,
              new_start_date,
              contract.end_date
            )

          update_factor =
            Indexes.compute_update_factor(contract.index_type, period.start_date, today)

          new_rent = Decimal.mult(period.value, update_factor)

          attrs = %{
            contract_id: contract.id,
            start_date: new_start_date,
            end_date: new_end_date,
            value: new_rent,
            index_type: contract.index_type,
            update_factor: update_factor
          }

          Contracts.create_rent_period(attrs)
          |> handle_create_result(attrs)
        end
    end
  end

  defp handle_create_result({:ok, %Vivvo.Contracts.RentPeriod{} = rent_period}, _attrs) do
    Logger.info(
      "RentPeriodCreationWorker: Created rent period #{rent_period.id} for contract #{rent_period.contract_id} " <>
        "(#{rent_period.start_date} to #{rent_period.end_date}, rent: #{rent_period.value})"
    )

    {:ok, rent_period}
  end

  defp handle_create_result({:ok, :already_exists}, attrs) do
    Logger.warning(
      "RentPeriodCreationWorker: Rent period already exists for contract #{attrs.contract_id} " <>
        "starting at #{attrs.start_date}, skipping due to unique constraint"
    )

    {:ok, :already_exists}
  end

  defp handle_create_result({:error, changeset}, attrs) do
    Logger.error(
      "RentPeriodCreationWorker: Failed to create rent period for contract #{attrs.contract_id}: #{inspect(changeset.errors)}"
    )

    {:error, changeset}
  end

  defp period_already_exists?(rent_periods, new_start_date) do
    Enum.any?(rent_periods, fn period ->
      Date.compare(period.start_date, new_start_date) == :eq
    end)
  end
end
