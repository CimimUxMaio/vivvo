defmodule Vivvo.PaymentsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Vivvo.Payments` context.
  """

  import Vivvo.ContractsFixtures, only: [contract_fixture: 2]

  @doc """
  Generate a payment.
  """
  def payment_fixture(scope, attrs \\ %{}) do
    contract =
      if Map.has_key?(attrs, :contract_id) do
        nil
      else
        contract_fixture(scope, %{tenant_id: scope.user.id})
      end

    attrs =
      Enum.into(attrs, %{
        amount: "120.5",
        notes: "some notes",
        payment_number: 42,
        status: :pending
      })

    attrs =
      if contract, do: Map.put(attrs, :contract_id, contract.id), else: attrs

    {:ok, payment} = Vivvo.Payments.create_payment(scope, attrs)
    payment
  end
end
