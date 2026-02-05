defmodule Vivvo.Properties.Property do
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
    |> put_change(:user_id, user_scope.user.id)
  end
end
