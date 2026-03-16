defmodule Vivvo.IndexService do
  @moduledoc """
  Service module for retrieving index values from the external Argly API.
  Supports fetching IPC and ICL index values for rent calculations.
  """

  @type index_type :: :ipc | :icl

  @base_url "https://api.argly.com.ar/api"

  @doc """
  Returns the list of available index types.

  This function serves as the single source of truth for all
  supported index types in the application.

  ## Examples

      iex> IndexService.index_types()
      [:ipc, :icl]
  """
  @spec index_types() :: list(index_type())
  def index_types, do: [:ipc, :icl]

  @doc """
  Returns the current/latest index value for the given index type.

  Makes an HTTP request to the /ipc or /icl endpoint and returns the parsed data.

  ## Returns

    * `{:ok, %{date: Date.t(), value: Decimal.t()}}` - Successfully fetched data
    * `{:error, reason}` - Failed to fetch or parse data

  ## Examples

      iex> IndexService.latest(:ipc)
      {:ok, %{date: ~D[2026-02-01], value: Decimal.new("2.9")}}
  """
  @spec latest(index_type()) :: {:ok, map()} | {:error, term()}
  def latest(index_type) do
    endpoint = endpoint_for_type(index_type)

    case Req.get(@base_url <> endpoint) do
      {:ok, %{status: 200, body: body}} ->
        parse_response(index_type, body)

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns historical index values for the given date range.

  The API returns monthly data from the start month to the end month (inclusive).

  ## Parameters

    * `index_type` - The type of index (:ipc or :icl)
    * `from` - Start date (not nil)
    * `to` - End date (not nil)

  ## Returns

    * `{:ok, list(%{date: Date.t(), value: Decimal.t()})}` - Successfully fetched data
    * `{:error, reason}` - Failed to fetch or parse data

  ## Examples

      iex> IndexService.history(:ipc, ~D[2025-03-01], ~D[2025-07-31])
      {:ok, [
        %{date: ~D[2025-03-01], value: Decimal.new("3.7")},
        %{date: ~D[2025-04-01], value: Decimal.new("2.8")},
        ...
      ]}
  """
  @spec history(index_type(), Date.t(), Date.t()) :: {:ok, list(map())} | {:error, term()}
  def history(_index_type, from, to) when is_nil(from) or is_nil(to),
    do: {:error, "From and To dates cannot be nil"}

  def history(index_type, from, to) do
    endpoint = endpoint_for_type(index_type)
    from_str = format_date_for_api(index_type, from)
    to_str = format_date_for_api(index_type, to)
    url = "#{@base_url}#{endpoint}/range?desde=#{from_str}&hasta=#{to_str}"

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        parse_response(index_type, body)

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp endpoint_for_type(:ipc), do: "/ipc"
  defp endpoint_for_type(:icl), do: "/icl"
  defp endpoint_for_type(other), do: raise(ArgumentError, "Unknown index type: #{inspect(other)}")

  defp format_date_for_api(:ipc, date) do
    # Format as YYYY-MM
    Date.to_iso8601(date)
    |> String.slice(0, 7)
  end

  defp format_date_for_api(:icl, date) do
    # Format as YYYY-MM-DD
    Date.to_iso8601(date)
  end

  # IPC latest endpoint format
  defp parse_index(:ipc = index_type, %{"anio" => year, "mes" => month, "indice_ipc" => val}) do
    with {:ok, year} <- parse_integer(year),
         {:ok, month} <- parse_integer(month),
         {:ok, date} <- Date.new(year, month, 1),
         {:ok, value} <- parse_decimal(val) do
      {:ok, %{type: index_type, date: date, value: value}}
    end
  end

  # IPC history endpoint format (uses "valor" instead of "indice_ipc")
  defp parse_index(:ipc = index_type, %{"anio" => year, "mes" => month, "valor" => val}) do
    with {:ok, year} <- parse_integer(year),
         {:ok, month} <- parse_integer(month),
         {:ok, date} <- Date.new(year, month, 1),
         {:ok, value} <- parse_decimal(val) do
      {:ok, %{type: index_type, date: date, value: value}}
    end
  end

  # ICL endpoint format
  defp parse_index(:icl = index_type, %{"fecha" => date, "valor" => val}) do
    with {:ok, date} <- parse_date(date),
         {:ok, value} <- parse_decimal(val) do
      {:ok, %{type: index_type, date: date, value: value}}
    end
  end

  defp parse_index(_index_type, index), do: {:error, "Unexpected index format: #{inspect(index)}"}

  defp parse_integer(val) when is_integer(val), do: {:ok, val}

  defp parse_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "Invalid integer: #{inspect(val)}"}
    end
  end

  defp parse_decimal(val) when is_float(val), do: {:ok, Decimal.from_float(val)}
  defp parse_decimal(val) when is_integer(val), do: {:ok, Decimal.new(val)}
  defp parse_decimal(val) when is_binary(val), do: {:ok, Decimal.new(val)}
  defp parse_decimal(val), do: {:error, "Invalid decimal: #{inspect(val)}"}

  defp parse_date(val) when is_binary(val) do
    # Handle DD/MM/YYYY format
    with [day, month, year] <- String.split(val, "/"),
         {:ok, day} <- parse_integer(day),
         {:ok, month} <- parse_integer(month),
         {:ok, year} <- parse_integer(year),
         {:ok, date} <- Date.new(year, month, day) do
      {:ok, date}
    else
      _ -> {:error, "Invalid date format: #{inspect(val)}"}
    end
  end

  defp parse_response(index_type, %{"data" => data}) when is_list(data) do
    result =
      data
      |> Enum.map(&parse_index(index_type, &1))
      |> Enum.reduce_while([], fn
        {:ok, item}, acc -> {:cont, [item | acc]}
        {:error, reason}, _acc -> {:halt, {:error, reason}}
      end)

    case result do
      {:error, _} = error -> error
      list -> {:ok, list}
    end
  end

  defp parse_response(index_type, %{"data" => data}) when is_map(data) do
    parse_index(index_type, data)
  end

  defp parse_response(_index_type, _), do: {:error, "Invalid response format"}
end
