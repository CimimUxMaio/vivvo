defmodule Vivvo.PropertiesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Vivvo.Properties` context.
  """

  @doc """
  Generate a property.
  """
  def property_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        address: "some address",
        area: 42,
        name: "some name",
        notes: "some notes",
        rooms: 42
      })

    {:ok, property} = Vivvo.Properties.create_property(scope, attrs)
    property
  end
end
