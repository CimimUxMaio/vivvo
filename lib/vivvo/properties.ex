defmodule Vivvo.Properties do
  @moduledoc """
  The Properties context.
  """

  import Ecto.Query, warn: false
  alias Vivvo.Repo

  alias Vivvo.Accounts.Scope
  alias Vivvo.Properties.Property

  @doc """
  Subscribes to scoped notifications about any property changes.

  The broadcasted messages match the pattern:

    * {:created, %Property{}}
    * {:updated, %Property{}}
    * {:deleted, %Property{}}

  """
  def subscribe_properties(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(Vivvo.PubSub, "user:#{key}:properties")
  end

  defp broadcast_property(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(Vivvo.PubSub, "user:#{key}:properties", message)
  end

  @doc """
  Returns the list of properties.

  ## Examples

      iex> list_properties(scope)
      [%Property{}, ...]

  """
  def list_properties(%Scope{} = scope) do
    Repo.all_by(Property, user_id: scope.user.id, archived: false)
  end

  @doc """
  Gets a single property.

  Raises `Ecto.NoResultsError` if the Property does not exist.

  ## Examples

      iex> get_property!(scope, 123)
      %Property{}

      iex> get_property!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_property!(%Scope{} = scope, id) do
    Repo.get_by!(Property, id: id, user_id: scope.user.id, archived: false)
  end

  @doc """
  Creates a property.

  ## Examples

      iex> create_property(scope, %{field: value})
      {:ok, %Property{}}

      iex> create_property(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_property(%Scope{} = scope, attrs) do
    with {:ok, property = %Property{}} <-
           %Property{}
           |> Property.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_property(scope, {:created, property})
      {:ok, property}
    end
  end

  @doc """
  Updates a property.

  ## Examples

      iex> update_property(scope, property, %{field: new_value})
      {:ok, %Property{}}

      iex> update_property(scope, property, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_property(%Scope{} = scope, %Property{} = property, attrs) do
    true = property.user_id == scope.user.id

    with {:ok, property = %Property{}} <-
           property
           |> Property.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_property(scope, {:updated, property})
      {:ok, property}
    end
  end

  @doc """
  Deletes a property.

  ## Examples

      iex> delete_property(scope, property)
      {:ok, %Property{}}

      iex> delete_property(scope, property)
      {:error, %Ecto.Changeset{}}

  """
  def delete_property(%Scope{} = scope, %Property{} = property) do
    true = property.user_id == scope.user.id

    with {:ok, property = %Property{}} <-
           property
           |> Property.archive_changeset(scope)
           |> Repo.update() do
      broadcast_property(scope, {:deleted, property})
      {:ok, property}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking property changes.

  ## Examples

      iex> change_property(scope, property)
      %Ecto.Changeset{data: %Property{}}

  """
  def change_property(%Scope{} = scope, %Property{} = property, attrs \\ %{}) do
    true = property.user_id == scope.user.id

    Property.changeset(property, attrs, scope)
  end
end
