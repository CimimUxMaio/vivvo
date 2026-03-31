defmodule VivvoWeb.Helpers.ContractHelpers do
  @moduledoc "Shared helper functions for contract-related UI"

  alias Vivvo.Contracts

  def index_type_label(nil), do: nil
  def index_type_label(:ipc), do: "IPC (Índice de Precios al Consumidor)"
  def index_type_label(:icl), do: "ICL (Índice de Contratos de Locación)"

  def rent_period_duration_label(nil), do: nil
  def rent_period_duration_label(1), do: "Monthly"
  def rent_period_duration_label(12), do: "Yearly"
  def rent_period_duration_label(months) when months > 1, do: "Every #{months} months"
  def rent_period_duration_label(_), do: nil

  def format_duration(start_date, end_date) do
    days = Date.diff(end_date, start_date)
    months = div(days, 30)
    years = div(months, 12)
    remaining_months = rem(months, 12)

    cond do
      years > 0 && remaining_months > 0 -> "#{years}y #{remaining_months}m"
      years > 0 -> "#{years} year#{if years > 1, do: "s"}"
      months > 0 -> "#{months} month#{if months > 1, do: "s"}"
      true -> "#{days} day#{if days != 1, do: "s"}"
    end
  end

  # Progress calculation functions

  @doc """
  Calculates contract progress percentage (0-100) based on current date.

  Returns 0 for contracts that haven't started yet, 100 for expired contracts,
  and the percentage of time elapsed for active contracts.
  """
  def calculate_contract_progress(contract, today) do
    total_days = Date.diff(contract.end_date, contract.start_date)
    elapsed_days = Date.diff(today, contract.start_date)

    cond do
      Date.compare(today, contract.start_date) == :lt -> 0
      Date.compare(today, contract.end_date) == :gt -> 100
      total_days == 0 -> 100
      true -> round(elapsed_days / total_days * 100)
    end
  end

  @doc """
  Calculates the position of the "today" marker on a progress bar as a percentage (0-100).

  Returns nil if today falls outside the contract period (before start or after end).
  """
  def calculate_today_marker(contract, today) do
    total_days = Date.diff(contract.end_date, contract.start_date)
    elapsed_days = Date.diff(today, contract.start_date)

    cond do
      Date.compare(today, contract.start_date) == :lt -> nil
      Date.compare(today, contract.end_date) == :gt -> nil
      total_days == 0 -> nil
      true -> round(elapsed_days / total_days * 100)
    end
  end

  @doc """
  Returns the color class for a given progress percentage.

  - <= 50%: success color (green)
  - 50-90%: warning color (yellow)
  - > 90%: error color (red)
  """
  def progress_color(progress) when progress <= 50, do: "bg-success"
  def progress_color(progress) when progress < 90, do: "bg-warning"
  def progress_color(_progress), do: "bg-error"

  @doc """
  Calculates timeline display data for progress labels.

  Returns a map with:
  - :days_until_start - days until contract starts (0 if already started)
  - :current_month - current payment month number
  - :total_months - total number of months in contract
  """
  def calculate_timeline_data(contract, today) do
    days_until_start =
      case Date.compare(contract.start_date, today) do
        :gt -> Date.diff(contract.start_date, today)
        _ -> 0
      end

    %{
      days_until_start: days_until_start,
      current_month: Contracts.get_current_payment_number(contract),
      total_months: Contracts.contract_duration_months(contract)
    }
  end

  # Timeline configuration functions

  def contract_timeline_config(contract_status) do
    case contract_status do
      :active ->
        %{status: :success, icon: "hero-check", label: "Active", contract_status: :active}

      :upcoming ->
        %{
          status: :info,
          icon: "hero-arrow-right",
          label: "Upcoming",
          contract_status: :upcoming
        }

      :expired ->
        %{status: :error, icon: "hero-archive-box", label: "Expired", contract_status: :expired}
    end
  end

  def payment_timeline_config(payment_status) do
    case payment_status do
      :accepted ->
        %{status: :success, icon: "hero-check", label: "Accepted", payment_status: :accepted}

      :pending ->
        %{status: :warning, icon: "hero-clock", label: "Pending", payment_status: :pending}

      :rejected ->
        %{status: :error, icon: "hero-x-mark", label: "Rejected", payment_status: :rejected}
    end
  end
end
