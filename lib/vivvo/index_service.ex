defmodule Vivvo.IndexService do
  @moduledoc """
  Service module for retrieving index values used in rent calculations.
  Supports fetching multiple index types efficiently for batch processing.
  """

  @type index_type :: :cpi | :fixed_percentage

  @doc """
  Returns the current index value for the given index type.

  ## Examples

      iex> IndexService.get_index_value(:cpi)
      Decimal.new("0.03")

      iex> IndexService.get_index_value(:fixed_percentage)
      Decimal.new("0.05")
  """
  @spec get_index_value(index_type()) :: Decimal.t()
  def get_index_value(:cpi), do: Decimal.new("0.03")
  def get_index_value(:fixed_percentage), do: Decimal.new("0.05")

  @doc """
  Fetches all available index values at once for efficient batch processing.

  Returns a map with all index types for use in workers processing multiple
  contracts with different index configurations.

  ## Examples

      iex> IndexService.get_all_index_values()
      %{cpi: Decimal.new("0.03"), fixed_percentage: Decimal.new("0.05")}
  """
  @spec get_all_index_values() :: %{index_type() => Decimal.t()}
  def get_all_index_values do
    %{
      cpi: get_index_value(:cpi),
      fixed_percentage: get_index_value(:fixed_percentage)
    }
  end
end
