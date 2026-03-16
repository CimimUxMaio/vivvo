defmodule Vivvo.Workers.RentPeriodSchedulerWorker do
  @moduledoc """
  Monthly cron worker that schedules rent period creation jobs.

  Runs at 12:00 PM on the 25th of each month. Pre-fetches all index
  values once, then schedules individual creation workers for each contract
  whose latest rent period ends in the current month. This proactively creates
  the next rent period before the current one expires, ensuring users always
  have access to current rent information.

  Uses unique constraint with year and month to prevent duplicate scheduling
  even if the server crashes and restarts.
  """

  use Oban.Worker,
    queue: :default,
    unique: [period: :infinity, keys: [:year, :month]]

  alias Vivvo.Contracts
  alias Vivvo.Indexes
  alias Vivvo.IndexService
  alias Vivvo.Workers.RentPeriodCreationWorker

  @impl Oban.Worker
  def perform(_job) do
    today = Date.utc_today()

    # Update index histories BEFORE processing contracts
    # This ensures we have the latest index data from external APIs
    update_index_histories(today)

    # Fetch ALL index values upfront (only 2 calls regardless of contract count)
    update_factors = fetch_all_update_factors()

    # Query all contracts needing rent period updates (all filtering done in database)
    contracts = Contracts.contracts_needing_update(today)

    # Schedule creation worker for each contract with pre-computed index value
    Enum.each(contracts, fn contract ->
      update_factor = Map.fetch!(update_factors, contract.index_type)

      %{
        contract_id: contract.id,
        update_factor: update_factor,
        year: today.year,
        month: today.month
      }
      |> RentPeriodCreationWorker.new(
        unique: [period: :infinity, keys: [:contract_id, :year, :month]],
        queue: :rent_periods
      )
      |> Oban.insert()
    end)

    {:ok, %{scheduled_count: length(contracts)}}
  end

  # Updates index histories for all index types by querying the external API
  # for values between the latest date in the database and today.
  # This should be done BEFORE processing contracts to ensure we have fresh data.
  defp update_index_histories(today) do
    require Logger

    with {:ok, missing_histories} <- fetch_missing_histories(today),
         {:ok, _count} <- Indexes.create_index_histories(missing_histories) do
      Logger.info(
        "Successfully updated index histories with #{length(missing_histories)} new entries"
      )
    else
      {:error, reason} ->
        Logger.error("Failed to update index histories: #{inspect(reason)}")
    end
  end

  defp fetch_missing_histories(today) do
    IndexService.index_types()
    |> Enum.map(fn type ->
      {from_date, to_date} = Indexes.get_missing_date_range(type, today)
      IndexService.history(type, from_date, to_date)
    end)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, histories}, {:ok, acc} ->
        {:cont, {:ok, acc ++ histories}}

      {:ok, _}, {:error, reason} ->
        {:halt, {:error, reason}}
    end)
  end

  # Builds a map of all available index values for efficient batch processing.
  # Fetches each index type and converts the percentage value to a decimal.
  defp fetch_all_update_factors do
    IndexService.index_types()
    |> Enum.map(fn index_type ->
      case IndexService.latest(index_type) do
        {:ok, %{value: value}} ->
          # Convert percentage to decimal (e.g., 2.9% -> 0.029)
          decimal_value = Decimal.div(value, 100)
          {index_type, decimal_value}

        {:error, _reason} ->
          # Fallback to default values if API fails
          {index_type, default_update_factor(index_type)}
      end
    end)
    |> Enum.into(%{})
  end

  defp default_update_factor(:ipc), do: Decimal.new("0.029")
  defp default_update_factor(:icl), do: Decimal.new("0.025")
end
