defmodule Vivvo.Files.File do
  @moduledoc """
  Schema for file attachments to payments.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Vivvo.Accounts.User
  alias Vivvo.Payments.Payment

  @allowed_extensions Application.compile_env(:vivvo, Vivvo.Files)[:allowed_extensions]

  schema "files" do
    field :label, :string
    field :path, :string

    belongs_to :user, User
    belongs_to :payment, Payment

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a file.

  ## Parameters
  - `file`: The File struct
  - `attrs`: Map with :label, :path, :payment_id, and :user_id

  ## Examples

      iex> File.changeset(%File{}, %{label: "receipt.pdf", path: "uploads/payments/uuid.pdf", payment_id: 1, user_id: 1})
      %Ecto.Changeset{}
  """
  def changeset(file, attrs) do
    file
    |> cast(attrs, [:label, :path, :payment_id, :user_id])
    |> validate_required([:label, :path, :user_id])
    |> validate_extension()
  end

  defp validate_extension(changeset) do
    path = get_field(changeset, :path)

    if path do
      extension =
        path
        |> Path.extname()
        |> String.downcase()
        |> String.trim_leading(".")

      if extension in @allowed_extensions do
        changeset
      else
        add_error(
          changeset,
          :path,
          "invalid file type. Allowed: #{Enum.join(@allowed_extensions, ", ")}"
        )
      end
    else
      changeset
    end
  end
end
