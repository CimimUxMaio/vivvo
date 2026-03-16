defmodule Vivvo.Indexes do
  @moduledoc """
  The Indexes context.

  Provides functionality for managing index history data,
  including querying and inserting historical index values
  from external APIs.
  """

  import Ecto.Query, warn: false
  alias Vivvo.Indexes.IndexHistory
  alias Vivvo.Repo

  @doc """
  Returns the list of all index histories.

  ## Examples

      iex> list_index_histories()
      [%IndexHistory{}, ...]

  """
  def list_index_histories do
    Repo.all(IndexHistory)
  end

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
  Gets a single index history by ID.

  Raises `Ecto.NoResultsError` if the IndexHistory does not exist.

  ## Examples

      iex> get_index_history!(123)
      %IndexHistory{}

      iex> get_index_history!(456)
      ** (Ecto.NoResultsError)

  """
  def get_index_history!(id), do: Repo.get!(IndexHistory, id)
end
