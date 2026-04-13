defmodule Vivvo.Workers.RentPeriodSchedulerWorker do
  @moduledoc """
  Monthly cron worker that schedules rent period creation jobs.

  Runs at 01:00 on the 1st of each month. Schedules individual creation
  workers for each contract whose latest rent period ended in the previous month.
  This creates new rent periods at the start of each month when the previous
  period has expired.

  The IndexHistoryWorker runs daily at 23:00 to ensure fresh index data is
  available before this worker executes.

  Scheduled via Oban Cron plugin which handles duplicate prevention automatically.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 7

  alias Vivvo.Contracts
  alias Vivvo.Workers.RentPeriodCreationWorker

  @max_backoff_seconds 43_200

  @impl Oban.Worker
  def perform(job) do
    today =
      case job.args do
        %{"today" => today_string} -> Date.from_iso8601!(today_string)
        _ -> Date.utc_today()
      end

    # Query all contracts needing rent period updates (all filtering done in database)
    contract_ids = Contracts.contracts_needing_update(today)

    # Schedule creation worker for each contract
    # Each worker will compute its own update factor based on contract's index type
    Enum.map(contract_ids, fn contract_id ->
      today_string = Date.to_iso8601(today)

      %{
        contract_id: contract_id,
        today: today_string
      }
      |> RentPeriodCreationWorker.new(
        unique: [period: :infinity, keys: [:contract_id, :today]],
        queue: :rent_periods
      )
    end)
    |> Oban.insert_all()

    {:ok, %{scheduled_count: length(contract_ids)}}
  end

  @impl Oban.Worker
  def backoff(%{attempt: attempt}) do
    # Exponential backoff: 15min, 30min, 1hr, 2hr, 4hr, 8hr, then cap at 12hr
    # Returns backoff in seconds
    base_backoff = 900
    backoff = trunc(base_backoff * :math.pow(2, attempt - 1))
    min(backoff, @max_backoff_seconds)
  end
end
