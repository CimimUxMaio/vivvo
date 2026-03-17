defmodule Vivvo.Workers.RentPeriodSchedulerWorker do
  @moduledoc """
  Monthly cron worker that schedules rent period creation jobs.

  Runs at 12:00 PM on the 25th of each month. Schedules individual creation
  workers for each contract whose latest rent period ends in the current month.
  This proactively creates the next rent period before the current one expires,
  ensuring users always have access to current rent information.

  Uses unique constraint with year and month to prevent duplicate scheduling
  even if the server crashes and restarts.
  """

  use Oban.Worker,
    queue: :default,
    unique: [period: :infinity, keys: [:year, :month]],
    max_attempts: 7

  alias Vivvo.Contracts
  alias Vivvo.Indexes
  alias Vivvo.IndexService
  alias Vivvo.Workers.RentPeriodCreationWorker

  @max_backoff_seconds 43_200

  @impl Oban.Worker
  def perform(job) do
    today =
      case job.args do
        %{"today" => today_string} -> Date.from_iso8601!(today_string)
        _ -> Date.utc_today()
      end

    # Update index histories BEFORE processing contracts
    # This ensures we have the latest index data from external APIs
    with {:ok, _} <- update_index_histories(today) do
      # Query all contracts needing rent period updates (all filtering done in database)
      contracts = Contracts.contracts_needing_update(today)

      # Schedule creation worker for each contract
      # Each worker will compute its own update factor based on contract's index type
      Enum.map(contracts, fn contract ->
        today_string = Date.to_iso8601(today)

        %{
          contract_id: contract.id,
          today: today_string
        }
        |> RentPeriodCreationWorker.new(
          unique: [period: :infinity, keys: [:contract_id, :today]],
          queue: :rent_periods
        )
      end)
      |> Oban.insert_all()

      {:ok, %{scheduled_count: length(contracts)}}
    end
  end

  @impl Oban.Worker
  def backoff(%{attempt: attempt}) do
    # Exponential backoff: 15min, 30min, 1hr, 2hr, 4hr, 8hr, then cap at 12hr
    # Returns backoff in seconds
    base_backoff = 900
    backoff = trunc(base_backoff * :math.pow(2, attempt - 1))
    min(backoff, @max_backoff_seconds)
  end

  # Updates index histories for all index types by querying the external API
  # for values between the latest date in the database and today.
  # This should be done BEFORE processing contracts to ensure we have fresh data.
  defp update_index_histories(today) do
    require Logger

    with {:ok, missing_histories} <- fetch_missing_histories(today),
         {:ok, count} <- Indexes.create_index_histories(missing_histories) do
      Logger.info(
        "Successfully updated index histories with #{length(missing_histories)} new entries"
      )

      {:ok, count}
    else
      {:error, reason} ->
        Logger.error("Failed to update index histories: #{inspect(reason)}")
        {:error, reason}
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
end
