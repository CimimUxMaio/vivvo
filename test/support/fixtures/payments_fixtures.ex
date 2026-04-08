defmodule Vivvo.PaymentsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Vivvo.Payments` context.
  """

  alias Vivvo.Payments

  import Vivvo.ContractsFixtures, only: [contract_fixture: 2]

  @valid_creation_attrs [
    :amount,
    :notes,
    :payment_number,
    :type,
    :category,
    :contract_id
  ]

  @doc """
  Generate a payment with pending status (default).

  Note: `:status` and `:rejection_reason` cannot be set during creation.
  Use `accepted_payment_fixture/2` or `rejected_payment_fixture/3` instead.
  """
  def payment_fixture(scope, attrs \\ %{}) do
    contract =
      if Map.has_key?(attrs, :contract_id) do
        nil
      else
        contract_fixture(scope, %{tenant_id: scope.user.id})
      end

    attrs =
      attrs
      |> Map.take(@valid_creation_attrs)
      |> Enum.into(%{
        amount: "120.5",
        notes: "some notes",
        payment_number: 42,
        type: :rent
      })

    attrs =
      if contract, do: Map.put(attrs, :contract_id, contract.id), else: attrs

    {:ok, payment} = Payments.create_payment(scope, attrs)
    payment
  end

  @doc """
  Generate an accepted payment by creating a pending one and then accepting it.
  """
  def accepted_payment_fixture(scope, attrs \\ %{}) do
    payment = payment_fixture(scope, attrs)
    {:ok, accepted} = Payments.accept_payment(scope, payment)
    accepted
  end

  @doc """
  Generate a rejected payment by creating a pending one and then rejecting it.
  """
  def rejected_payment_fixture(scope, attrs \\ %{}, reason \\ "Test rejection") do
    payment = payment_fixture(scope, attrs)
    {:ok, rejected} = Payments.reject_payment(scope, payment, reason)
    rejected
  end
end
