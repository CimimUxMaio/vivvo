defmodule VivvoWeb.Helpers.LiveView do
  @moduledoc """
  Shared helper functions for LiveView modules.

  This module provides common utility functions for managing LiveView
  UI state and behavior, particularly around modal interactions.
  """

  @doc """
  Opens a modal by pushing the "modal:open" event to the client.

  ## Parameters

    * `socket` - The LiveView socket
    * `modal_id` - The DOM ID of the modal to open

  ## Examples

      iex> push_modal_open(socket, "reject-payment-modal")
      # Pushes modal:open event to the client

  """
  @spec push_modal_open(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def push_modal_open(socket, modal_id) do
    Phoenix.LiveView.push_event(socket, "modal:open", %{id: modal_id})
  end

  @doc """
  Closes a modal by pushing the "modal:close" event to the client.

  ## Parameters

    * `socket` - The LiveView socket
    * `modal_id` - The DOM ID of the modal to close

  ## Examples

      iex> push_modal_close(socket, "reject-payment-modal")
      # Pushes modal:close event to the client

  """
  @spec push_modal_close(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def push_modal_close(socket, modal_id) do
    Phoenix.LiveView.push_event(socket, "modal:close", %{id: modal_id})
  end
end
