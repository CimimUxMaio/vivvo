defmodule Vivvo.Payments.Helpers do
  @moduledoc """
  Helper functions for payment-related calculations and comparisons.

  This module provides utility functions for comparing Decimal amounts
  and determining payment statuses, reducing code duplication across
  the payments context and LiveView templates.
  """

  alias Decimal

  @doc """
  Compares two Decimal amounts and returns an atom representing the relationship.

  ## Examples

      iex> compare_amount(Decimal.new("100"), Decimal.new("100"))
      :equal

      iex> compare_amount(Decimal.new("150"), Decimal.new("100"))
      :greater

      iex> compare_amount(Decimal.new("50"), Decimal.new("100"))
      :less
  """
  @spec compare_amount(Decimal.t(), Decimal.t()) :: :equal | :greater | :less
  def compare_amount(amount1, amount2) do
    case Decimal.compare(amount1, amount2) do
      :eq -> :equal
      :gt -> :greater
      :lt -> :less
    end
  end

  @doc """
  Determines the payment status based on paid amount vs expected amount.

  ## Examples

      iex> payment_status(Decimal.new("100"), Decimal.new("100"))
      :correct

      iex> payment_status(Decimal.new("150"), Decimal.new("100"))
      :overpaid

      iex> payment_status(Decimal.new("50"), Decimal.new("100"))
      :underpaid
  """
  @spec payment_status(Decimal.t(), Decimal.t()) :: :correct | :overpaid | :underpaid
  def payment_status(paid, expected) do
    case Decimal.compare(paid, expected) do
      :eq -> :correct
      :gt -> :overpaid
      :lt -> :underpaid
    end
  end

  @doc """
  Checks if an amount is greater than zero.

  ## Examples

      iex> positive?(Decimal.new("100"))
      true

      iex> positive?(Decimal.new("0"))
      false

      iex> positive?(Decimal.new("-50"))
      false
  """
  @spec positive?(Decimal.t()) :: boolean()
  def positive?(amount) do
    Decimal.gt?(amount, Decimal.new(0))
  end

  @doc """
  Checks if an amount is zero.

  ## Examples

      iex> zero?(Decimal.new("0"))
      true

      iex> zero?(Decimal.new("100"))
      false
  """
  @spec zero?(Decimal.t()) :: boolean()
  def zero?(amount) do
    Decimal.eq?(amount, Decimal.new(0))
  end

  @doc """
  Calculates the percentage of received amount relative to expected amount.
  Returns a float between 0.0 and 100.0.

  ## Examples

      iex> percentage(Decimal.new("75"), Decimal.new("100"))
      75.0

      iex> percentage(Decimal.new("150"), Decimal.new("100"))
      100.0

      iex> percentage(Decimal.new("0"), Decimal.new("100"))
      0.0
  """
  @spec percentage(Decimal.t(), Decimal.t()) :: float()
  def percentage(received, expected) do
    if Decimal.gt?(expected, Decimal.new(0)) do
      received
      |> Decimal.div(expected)
      |> Decimal.mult(Decimal.new(100))
      |> Decimal.to_float()
      |> min(100.0)
    else
      0.0
    end
  end
end
