defmodule VivvoWeb.Helpers.ContractHelpers do
  @moduledoc "Shared helper functions for contract-related UI"

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
