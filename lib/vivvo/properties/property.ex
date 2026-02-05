defmodule Vivvo.Properties.Property do
  @moduledoc """
  Schema for properties owned by users.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Vivvo.Accounts.User

  schema "properties" do
    field :name, :string
    field :address, :string
    field :area, :integer
    field :rooms, :integer
    field :notes, :string, default: ""

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(property, attrs, user_scope) do
    property
    |> cast(attrs, [:name, :address, :area, :rooms, :notes])
    |> validate_required([:name, :address])
    |> validate_number(:area, greater_than: 0)
    |> validate_number(:rooms, greater_than: 0)
    |> put_change(:user_id, user_scope.user.id)
  end
end
