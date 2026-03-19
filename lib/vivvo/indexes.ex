defmodule Vivvo.Indexes do
  @moduledoc """
  The Indexes context.

  Provides functionality for managing index history data,
  including querying and inserting historical index values
  from external APIs.
  """

  import Ecto.Query, warn: false
  require Logger
  alias Vivvo.Indexes.IndexHistory
  alias Vivvo.Repo

  @doc """
  Returns the list of index histories filtered by index type.

  ## Examples

      iex> list_index_histories_by_type(:ipc)
      [%IndexHistory{type: :ipc}, ...]

  """
  def list_index_histories_by_type(type) do
    IndexHistory
    |> where([ih], ih.type == ^type)
    |> order_by([ih], asc: ih.date)
    |> Repo.all()
  end

  @doc """
  Gets the latest date for a given index type.

  Returns `nil` if no records exist for the index type.

  ## Examples

      iex> get_latest_date(:ipc)
      ~D[2026-02-01]

      iex> get_latest_date(:unknown_type)
      nil

  """
  def get_latest_date(type) do
    IndexHistory
    |> where([ih], ih.type == ^type)
    |> select([ih], max(ih.date))
    |> Repo.one()
  end

  @doc """
  Creates a single index history record.

  ## Examples

      iex> create_index_history(%{type: :ipc, value: "2.9", date: ~D[2026-02-01]})
      {:ok, %IndexHistory{}}

      iex> create_index_history(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_index_history(attrs) do
    %IndexHistory{}
    |> IndexHistory.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates multiple index history records atomically using Repo.insert_all.

  This is more efficient than inserting records one at a time and ensures
  all records are inserted together or none at all.

  ## Examples

      iex> create_index_histories([
      ...>   %{type: :ipc, value: "2.9", date: ~D[2026-02-01]},
      ...>   %{type: :ipc, value: "3.0", date: ~D[2026-03-01]}
      ...> ])
      {:ok, 2}

      iex> create_index_histories([])
      {:ok, 0}

  """
  def create_index_histories([]), do: {:ok, 0}

  def create_index_histories(attrs_list) when is_list(attrs_list) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(attrs_list, fn attrs ->
        Map.merge(attrs, %{
          inserted_at: now,
          updated_at: now
        })
      end)

    {count, nil} = Repo.insert_all(IndexHistory, entries, on_conflict: :nothing)
    {:ok, count}
  end

  @doc """
  Returns a date range tuple {from_date, to_date} representing the missing
  dates between the latest stored date for an index type and the given end date.

  If no records exist for the index type, returns a default start date
  (2 years ago from the end date).

  ## Examples

      iex> get_missing_date_range(:ipc, ~D[2026-03-15])
      {~D[2026-02-01], ~D[2026-03-15]}  # when latest date is 2026-02-01

      iex> get_missing_date_range(:ipc, ~D[2026-03-15])
      {~D[2024-03-15], ~D[2026-03-15]}  # when no records exist

  """
  def get_missing_date_range(type, end_date) do
    from_date =
      case get_latest_date(type) do
        nil ->
          # Default to 2 years ago if no records exist
          Date.shift(end_date, year: -2)

        latest_date ->
          # Start from the day after the latest date
          Date.add(latest_date, 1)
      end

    {from_date, end_date}
  end

  @doc """
  Returns index histories for a given type within a date range (inclusive).

  Results are ordered by date in ascending order.

  ## Examples

      iex> get_index_history_by_date_range(:ipc, ~D[2026-01-01], ~D[2026-03-01])
      [%IndexHistory{date: ~D[2026-01-01], value: Decimal.new("2.5")}, ...]

  """
  def get_index_history_by_date_range(type, start_date, end_date) do
    IndexHistory
    |> where([ih], ih.type == ^type)
    |> where([ih], ih.date >= ^start_date)
    |> where([ih], ih.date <= ^end_date)
    |> order_by([ih], asc: ih.date)
    |> Repo.all()
  end

  @doc """
  Gets the index history value for a specific type and exact date.

  Returns nil if no record exists for the given type and date.

  ## Examples

      iex> get_index_history_by_date(:icl, ~D[2026-02-01])
      %IndexHistory{value: Decimal.new("150.5")}

      iex> get_index_history_by_date(:icl, ~D[2020-01-01])
      nil

  """
  def get_index_history_by_date(type, date) do
    IndexHistory
    |> where([ih], ih.type == ^type and ih.date == ^date)
    |> Repo.one()
  end

  @doc """
  Gets the latest index history record for a given type.

  Returns nil if no records exist for the index type.

  ## Examples

      iex> get_latest_index_value(:icl)
      %IndexHistory{date: ~D[2026-03-01], value: Decimal.new("155.2")}

      iex> get_latest_index_value(:unknown)
      nil

  """
  def get_latest_index_value(type, today \\ Date.utc_today()) do
    IndexHistory
    |> where([ih], ih.type == ^type)
    |> where([ih], ih.date <= ^today)
    |> order_by([ih], desc: ih.date)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Computes the update factor for a given index type.

  For IPC: Accumulates historic rates between last_update date and previous month end.

  For ICL: Calculates the ratio between the latest value and the value at the last_update date.
  Returns (latest_value / old_value) as decimal.

  ## Examples

      iex> compute_update_factor(:ipc, ~D[2026-01-01], ~D[2026-03-15])
      Decimal.new("0.055")  # (1 + ipc_month1) * (1 + ipc_month2) * ... = 0.055

      iex> compute_update_factor(:icl, ~D[2026-01-01])
      Decimal.new("0.10")   # current_value / old_value

  """
  def compute_update_factor(type, last_update, today \\ Date.utc_today())

  def compute_update_factor(:ipc, last_update, today) do
    # Day 1-15: Include the month (typical for rent period start on 1st)
    # Day 16-31: Skip the month (first month grace period)
    start_date =
      if last_update.day <= 15 do
        Date.beginning_of_month(last_update)
      else
        last_update
        |> Date.beginning_of_month()
        |> Date.shift(month: 1)
      end

    # Always exclude today's month (current month rate is not yet finalized)
    end_date =
      today
      |> Date.beginning_of_month()
      |> Date.add(-1)

    if Date.compare(end_date, start_date) == :lt do
      Decimal.new(1)
    else
      histories = get_index_history_by_date_range(:ipc, start_date, end_date)
      accumulate_rates(histories)
    end
  end

  def compute_update_factor(:icl, last_update, today) do
    old_history = get_index_history_by_date(:icl, last_update)
    new_history = get_latest_index_value(:icl, today)

    if is_nil(old_history) do
      raise ArgumentError,
            "No ICL history found for date #{inspect(last_update)}, cannot compute update factor"
    end

    if is_nil(new_history) do
      raise ArgumentError,
            "No latest ICL history found for date #{inspect(today)}, cannot compute update factor"
    end

    Decimal.div(new_history.value, old_history.value)
  end

  def compute_update_factor(type, _last_update, _today) do
    raise ArgumentError, "Unsupported index type: #{type}"
  end

  defp accumulate_rates([]), do: Decimal.new(1)

  defp accumulate_rates(histories) do
    Enum.reduce(histories, Decimal.new(1), fn history, acc ->
      rate_as_decimal = Decimal.div(history.value, 100)

      Decimal.add(1, rate_as_decimal)
      |> Decimal.mult(acc)
    end)
  end
end
