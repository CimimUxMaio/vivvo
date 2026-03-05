defmodule VivvoWeb.PaymentComponents do
  @moduledoc """
  Provides reusable UI components for payment-related views.

  These components ensure consistent styling across tenant and owner dashboards
  while maintaining flexibility for different layouts.
  """

  use VivvoWeb, :html

  @doc """
  Renders a styled file chip for displaying attached payment files.

  ## Examples

      <.file_chip file={file} />

  """
  attr :file, :map, required: true, doc: "The file map with :id and :label keys"

  def file_chip(assigns) do
    ~H"""
    <a
      href={~p"/files/#{@file.id}"}
      target="_blank"
      class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-base-100 rounded-lg border border-base-300 text-xs cursor-pointer transition-all duration-200 hover:bg-primary/10 hover:border-primary/30 hover:shadow-sm hover:scale-[1.02] group/file"
    >
      <.icon
        name="hero-document"
        class="w-4 h-4 text-base-content/50 group-hover/file:text-primary"
      />
      <span
        class="text-base-content/80 truncate max-w-[120px] sm:max-w-[180px]"
        title={@file.label}
      >
        {@file.label}
      </span>
      <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3 text-base-content/30" />
    </a>
    """
  end
end
