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
  alias Vivvo.IndexService
  alias Vivvo.Workers.RentPeriodCreationWorker

  @impl Oban.Worker
  def perform(_job) do
    today = Date.utc_today()

    # Fetch ALL index values upfront (only 2 calls regardless of contract count)
    index_values = IndexService.get_all_index_values()

    # Query all contracts needing rent period updates (all filtering done in database)
    contracts = Contracts.contracts_needing_update(today)

    # Schedule creation worker for each contract with pre-computed index value
    Enum.each(contracts, fn contract ->
      index_value = Map.fetch!(index_values, contract.index_type)

      %{
        contract_id: contract.id,
        index_value: index_value,
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
end
