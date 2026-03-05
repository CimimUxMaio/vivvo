defmodule Vivvo.FilesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Vivvo.Files` context.
  """

  alias Vivvo.PaymentsFixtures

  @doc """
  Generate a file.
  """
  def file_fixture(scope, attrs \\ %{}) do
    # Create a payment first if not provided
    payment_id =
      case Map.get(attrs, :payment_id) || Map.get(attrs, "payment_id") do
        nil ->
          payment = PaymentsFixtures.payment_fixture(scope)
          payment.id

        id ->
          id
      end

    attrs =
      attrs
      |> Enum.into(%{
        "label" => "receipt.pdf",
        "path" => "uploads/payments/test-file.pdf",
        "payment_id" => payment_id
      })

    {:ok, file} = Vivvo.Files.create_file(scope, attrs)
    file
  end
end
