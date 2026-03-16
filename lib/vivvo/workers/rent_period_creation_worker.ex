defmodule Vivvo.Workers.RentPeriodCreationWorker do
  @moduledoc """
  Worker that creates a new rent period for a specific contract.

  Receives pre-computed index value from scheduler to avoid redundant
  IndexService calls. Performs idempotency checks to prevent duplicate
  rent periods.

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

  require Logger

  @impl Oban.Worker
  def perform(%{
        args: %{
          "contract_id" => contract_id,
          "update_factor" => update_factor,
          "year" => year,
          "month" => month
        }
      }) do
    case Contracts.get_system_contract(contract_id) do
      nil ->
        Logger.warning("RentPeriodCreationWorker: Contract #{contract_id} not found, skipping")
        {:ok, :contract_not_found}

      contract ->
        create_rent_period_for_contract(contract, update_factor, year, month)
    end
  end

  defp create_rent_period_for_contract(contract, update_factor, year, month) do
    # Find the period ending in the scheduler's year/month
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
          do_create_rent_period(contract, update_factor, period, new_start_date)
        end
    end
  end

  defp do_create_rent_period(contract, update_factor, previous_period, new_start_date) do
    new_end_date =
      calculate_period_end(new_start_date, contract.rent_period_duration, contract.end_date)

    new_rent = calculate_new_rent(previous_period.value, update_factor)

    attrs = %{
      contract_id: contract.id,
      start_date: new_start_date,
      end_date: new_end_date,
      value: new_rent,
      index_type: contract.index_type,
      update_factor: update_factor
    }

    Contracts.create_rent_period(attrs)
    |> handle_create_result(
      contract.id,
      new_start_date,
      new_end_date,
      new_rent
    )
  end

  defp handle_create_result(
         {:ok, rent_period},
         contract_id,
         new_start_date,
         new_end_date,
         new_rent
       ) do
    Logger.info(
      "RentPeriodCreationWorker: Created rent period #{rent_period.id} for contract #{contract_id} " <>
        "(#{new_start_date} to #{new_end_date}, rent: #{new_rent})"
    )

    {:ok, rent_period}
  end

  defp handle_create_result({:error, changeset}, contract_id, _start_date, _end_date, _rent) do
    Logger.error(
      "RentPeriodCreationWorker: Failed to create rent period for contract #{contract_id}: #{inspect(changeset.errors)}"
    )

    {:error, changeset}
  end

  defp period_already_exists?(rent_periods, new_start_date) do
    Enum.any?(rent_periods, fn period ->
      Date.compare(period.start_date, new_start_date) == :eq
    end)
  end

  defp calculate_period_end(start_date, duration, contract_end_date) do
    start_date
    |> Date.shift(month: duration - 1)
    |> Date.end_of_month()
    |> then(&Enum.min([&1, contract_end_date], Date))
  end

  defp calculate_new_rent(previous_value, update_factor) do
    multiplier = Decimal.add(1, update_factor)
    Decimal.mult(previous_value, multiplier)
  end
end
