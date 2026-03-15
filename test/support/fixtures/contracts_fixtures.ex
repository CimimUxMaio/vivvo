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
  def contract_fixture(scope, attrs \\ %{}, opts \\ []) do
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
      # Start from today to ensure the contract covers the current date
      start_date: today,
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

    {:ok, contract} = Vivvo.Contracts.create_contract(scope, attrs, opts)
    contract
  end

  @doc """
  Generate an expired contract (end_date in the past).
  """
  def expired_contract_fixture(scope, attrs \\ %{}) do
    today = Date.utc_today()

    merged_attrs =
      Map.merge(
        %{
          start_date: Date.add(today, -60),
          end_date: Date.add(today, -1),
          index_type: :icl,
          rent_period_duration: 12
        },
        attrs
      )

    contract_fixture(
      scope,
      merged_attrs,
      past_start_date?: true,
      index_value: Decimal.new("0.0")
    )
  end

  @doc """
  Generate a rent period for a contract.
  """
  def rent_period_fixture(contract, attrs \\ %{}) do
    today = Date.utc_today()

    default_attrs = %{
      contract_id: contract.id,
      start_date: Date.add(today, -30),
      end_date: today,
      value: Decimal.new("1000.00"),
      index_type: contract.index_type,
      index_value: nil
    }

    attrs = Enum.into(attrs, default_attrs)

    {:ok, rent_period} = Vivvo.Contracts.create_rent_period(attrs)
    rent_period
  end
end
