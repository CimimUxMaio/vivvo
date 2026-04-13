defmodule Vivvo.Workers.IndexHistoryWorker do
  @moduledoc """
  Daily cron worker that updates index histories from external APIs.

  Runs at 23:00 each day to fetch the latest index data before the
  rent period updates run on the 1st of each month at 01:00.

  Fetches missing index history data for all index types (IPC, ICL)
  between the latest date in the database and today.

  Scheduled via Oban Cron plugin which handles duplicate prevention automatically.
  """

  require Logger

  use Oban.Worker,
    queue: :default,
    max_attempts: 7

  alias Vivvo.Indexes
  alias Vivvo.IndexService

  @max_backoff_seconds 43_200

  @impl Oban.Worker
  def perform(job) do
    today =
      case job.args do
        %{"today" => today_string} -> Date.from_iso8601!(today_string)
        _ -> Date.utc_today()
      end

    with {:ok, _} <- update_index_histories(today) do
      {:ok, :ok}
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
  defp update_index_histories(today) do
    with {:ok, missing_histories} <- fetch_missing_histories(today),
         {:ok, count} <- Indexes.create_index_histories(missing_histories) do
      Logger.info(
        "IndexHistoryWorker: Successfully updated index histories with #{length(missing_histories)} new entries"
      )

      {:ok, count}
    else
      {:error, reason} ->
        Logger.error("IndexHistoryWorker: Failed to update index histories: #{inspect(reason)}")
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

      {:error, reason}, _acc ->
        {:halt, {:error, reason}}
    end)
  end
end
