defmodule Vivvo.Indexes.IndexHistory do
  @moduledoc """
  Schema for storing historic values of different indexes (IPC, ICL, etc.)
  from the external Argly API.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "index_histories" do
    field :type, Ecto.Enum, values: [:ipc, :icl]
    field :value, :decimal
    field :date, :date

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(index_history, attrs) do
    index_history
    |> cast(attrs, [:type, :value, :date])
    |> validate_required([:type, :value, :date])
    |> unique_constraint([:type, :date],
      name: :index_histories_type_date_index,
      message: "index history already exists for this type and date"
    )
  end
end
