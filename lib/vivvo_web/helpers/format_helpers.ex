defmodule VivvoWeb.FormatHelpers do
  @moduledoc """
  Shared helper functions for formatting data in templates.

  This module provides consistent formatting for dates, times, and other
  common data types used across the application.
  """

  @doc """
  Formats a date using the specified format string.

  ## Examples

      iex> format_date(~D[2026-02-07])
      "Feb 07, 2026"

      iex> format_date(~D[2026-02-07], "%Y-%m-%d")
      "2026-02-07"

      iex> format_date(nil)
      ""
  """
  def format_date(date, format \\ "%b %d, %Y")
  def format_date(nil, _format), do: ""

  def format_date(date, format) do
    Calendar.strftime(date, format)
  end

  @doc """
  Formats a datetime using the specified format string.

  ## Examples

      iex> format_datetime(~U[2026-02-07 14:30:00Z])
      "Feb 07, 2026 02:30 PM"

      iex> format_datetime(~U[2026-02-07 14:30:00Z], "%Y-%m-%d %H:%M")
      "2026-02-07 14:30"

      iex> format_datetime(nil)
      ""
  """
  def format_datetime(datetime, format \\ "%b %d, %Y %I:%M %p")
  def format_datetime(nil, _format), do: ""

  def format_datetime(datetime, format) do
    Calendar.strftime(datetime, format)
  end

  @doc """
  Formats a datetime for display in a user-friendly way.
  Shows relative time for recent dates (today, yesterday) 
  and full date for older ones.

  ## Examples

      iex> format_relative(~U[2026-02-07 14:30:00Z], ~D[2026-02-07])
      "Today at 02:30 PM"
  """
  def format_relative(datetime, reference_date \\ Date.utc_today())
  def format_relative(nil, _reference_date), do: ""

  def format_relative(datetime, reference_date) do
    date = DateTime.to_date(datetime)

    cond do
      Date.compare(date, reference_date) == :eq ->
        "Today at #{Calendar.strftime(datetime, "%I:%M %p")}"

      Date.compare(date, Date.add(reference_date, -1)) == :eq ->
        "Yesterday at #{Calendar.strftime(datetime, "%I:%M %p")}"

      true ->
        format_datetime(datetime)
    end
  end

  @doc """
  Formats the number of days until a date into a human-friendly string.

  ## Examples

      iex> format_time_until(5)
      "in 5 days"

      iex> format_time_until(1)
      "tomorrow"

      iex> format_time_until(0)
      "today"

      iex> format_time_until(-2)
      "2 days ago"

      iex> format_time_until(nil)
      ""
  """
  def format_time_until(nil), do: ""

  def format_time_until(days) when is_integer(days) do
    cond do
      days < 0 -> "#{days * -1} days ago"
      days == 0 -> "today"
      days == 1 -> "tomorrow"
      true -> "in #{days} days"
    end
  end

  @doc """
  Formats a monetary amount as USD currency.

  ## Examples

      iex> format_currency(Decimal.new("1234.56"))
      "$1,234.56"

      iex> format_currency(100)
      "$100.00"

      iex> format_currency(1234.56)
      "$1,234.56"

      iex> format_currency(nil)
      "$0.00"
  """
  def format_currency(nil), do: "$0.00"

  def format_currency(amount) when is_struct(amount, Decimal) do
    amount
    |> Decimal.to_float()
    |> format_currency()
  end

  def format_currency(amount) when is_float(amount) or is_integer(amount) do
    # Convert to float and format with 2 decimal places
    formatted = :erlang.float_to_binary(amount * 1.0, decimals: 2)

    # Add thousands separator
    [dollars, cents] = String.split(formatted, ".")

    dollars_with_commas =
      dollars
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map_join(",", &Enum.join(&1, ""))
      |> String.reverse()

    "$#{dollars_with_commas}.#{cents}"
  end
end
