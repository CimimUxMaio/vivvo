defmodule Vivvo.ContractsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Vivvo.Contracts` context.
  """

  import Vivvo.AccountsFixtures, only: [user_fixture: 1]
  import Vivvo.PropertiesFixtures, only: [property_fixture: 1]

  @doc """
  Generate a contract.
  """
  def contract_fixture(scope, attrs \\ %{}) do
    # Create tenant and property if not provided
    tenant =
      if Map.has_key?(attrs, :tenant_id) do
        nil
      else
        user_fixture(%{preferred_roles: [:tenant]})
      end

    property =
      if Map.has_key?(attrs, :property_id) do
        nil
      else
        property_fixture(scope)
      end

    today = Date.utc_today()

    default_attrs = %{
      start_date: Date.add(today, 1),
      end_date: Date.add(today, 30),
      expiration_day: 5,
      notes: "some notes",
      rent: "120.5"
    }

    default_attrs =
      if tenant, do: Map.put(default_attrs, :tenant_id, tenant.id), else: default_attrs

    default_attrs =
      if property, do: Map.put(default_attrs, :property_id, property.id), else: default_attrs

    attrs = Enum.into(attrs, default_attrs)

    {:ok, contract} = Vivvo.Contracts.create_contract(scope, attrs)
    contract
  end
end
