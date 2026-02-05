defmodule Vivvo.Contracts do
  @moduledoc """
  The Contracts context.
  """

  import Ecto.Query, warn: false
  alias Vivvo.Repo

  alias Vivvo.Accounts.Scope
  alias Vivvo.Contracts.Contract

  @doc """
  Subscribes to scoped notifications about any contract changes.

  The broadcasted messages match the pattern:

    * {:created, %Contract{}}
    * {:updated, %Contract{}}
    * {:deleted, %Contract{}}

  """
  def subscribe_contracts(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(Vivvo.PubSub, "user:#{key}:contracts")
  end

  defp broadcast_contract(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(Vivvo.PubSub, "user:#{key}:contracts", message)
  end

  @doc """
  Returns the list of contracts.

  ## Examples

      iex> list_contracts(scope)
      [%Contract{}, ...]

  """
  def list_contracts(%Scope{} = scope) do
    Repo.all_by(Contract, user_id: scope.user.id, archived: false)
  end

  @doc """
  Gets a single contract.

  Raises `Ecto.NoResultsError` if the Contract does not exist.

  ## Examples

      iex> get_contract!(scope, 123)
      %Contract{}

      iex> get_contract!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_contract!(%Scope{} = scope, id) do
    Repo.get_by!(Contract, id: id, user_id: scope.user.id, archived: false)
  end

  @doc """
  Gets the active contract for a specific property.

  Returns nil if no active contract exists, or the contract struct with tenant preloaded.

  ## Examples

      iex> get_contract_for_property(scope, 123)
      %Contract{tenant: %User{}}

      iex> get_contract_for_property(scope, 456)
      nil
  """
  def get_contract_for_property(%Scope{} = scope, property_id) do
    from(c in Contract,
      where:
        c.property_id == ^property_id and c.user_id == ^scope.user.id and c.archived == false,
      preload: [:tenant]
    )
    |> Repo.one()
  end

  @doc """
  Creates a contract.

  ## Examples

      iex> create_contract(scope, %{field: value})
      {:ok, %Contract{}}

      iex> create_contract(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_contract(%Scope{} = scope, attrs) do
    property_id = get_property_id(attrs)
    old_contract = maybe_get_contract_for_property(scope, property_id)

    result =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:archive_old, maybe_archive_old_contract(scope, old_contract))
      |> Ecto.Multi.insert(:contract, Contract.changeset(%Contract{}, attrs, scope))
      |> Repo.transaction()

    case result do
      {:ok, %{contract: contract}} ->
        broadcast_contract(scope, {:created, contract})

        unless is_nil(old_contract) do
          broadcast_contract(scope, {:deleted, old_contract})
        end

        {:ok, contract}

      {:error, _name, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp maybe_archive_old_contract(_scope, nil) do
    fn _repo, _changes ->
      {:ok, :no_existing_contract}
    end
  end

  defp maybe_archive_old_contract(%Scope{} = scope, %Contract{} = old_contract) do
    fn repo, _changes ->
      old_contract
      |> Contract.archive_changeset(scope)
      |> repo.update()
    end
  end

  defp get_property_id(attrs) do
    Map.get(attrs, "property_id") || Map.get(attrs, :property_id)
  end

  defp maybe_get_contract_for_property(_scope, nil), do: nil

  defp maybe_get_contract_for_property(%Scope{} = scope, property_id) do
    get_contract_for_property(scope, property_id)
  end

  @doc """
  Updates a contract.

  ## Examples

      iex> update_contract(scope, contract, %{field: new_value})
      {:ok, %Contract{}}

      iex> update_contract(scope, contract, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_contract(%Scope{} = scope, %Contract{} = contract, attrs) do
    true = contract.user_id == scope.user.id

    with {:ok, contract = %Contract{}} <-
           contract
           |> Contract.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_contract(scope, {:updated, contract})
      {:ok, contract}
    end
  end

  @doc """
  Deletes a contract.

  ## Examples

      iex> delete_contract(scope, contract)
      {:ok, %Contract{}}

      iex> delete_contract(scope, contract)
      {:error, %Ecto.Changeset{}}

  """
  def delete_contract(%Scope{} = scope, %Contract{} = contract) do
    true = contract.user_id == scope.user.id

    with {:ok, contract = %Contract{}} <-
           contract
           |> Contract.archive_changeset(scope)
           |> Repo.update() do
      broadcast_contract(scope, {:deleted, contract})
      {:ok, contract}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking contract changes.

  ## Examples

      iex> change_contract(scope, contract)
      %Ecto.Changeset{data: %Contract{}}

  """
  def change_contract(%Scope{} = scope, %Contract{} = contract, attrs \\ %{}) do
    if contract.user_id, do: true = contract.user_id == scope.user.id

    Contract.changeset(contract, attrs, scope)
  end

  @doc """
  Returns the current status of a contract based on its dates.

  ## Return Values
  - `:upcoming` - start_date is in the future
  - `:active` - today is between start_date and end_date
  - `:expired` - end_date is in the past

  ## Examples

      iex> contract_status(%Contract{start_date: ~D[2026-03-01], end_date: ~D[2027-03-01]})
      :upcoming
  """
  def contract_status(%Contract{} = contract) do
    today = Date.utc_today()

    cond do
      Date.compare(today, contract.start_date) == :lt -> :upcoming
      Date.compare(today, contract.end_date) == :gt -> :expired
      true -> :active
    end
  end

  @doc """
  Checks if the current monthly payment is overdue based on expiration_day.

  Only relevant if contract is :active. Checks if current day of month
  is past the expiration_day.

  ## Examples

      iex> payment_overdue?(%Contract{expiration_day: 5})
      true  # if today is after the 5th of current month
  """
  def payment_overdue?(%Contract{} = contract) do
    today = Date.utc_today()
    today.day > contract.expiration_day
  end
end
