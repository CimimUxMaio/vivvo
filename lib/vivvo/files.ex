defmodule Vivvo.Files do
  @moduledoc """
  The Files context.
  """

  import Ecto.Query, warn: false
  alias Vivvo.Repo

  # Alias the schema as FileRecord to avoid conflicts with Elixir's File module
  alias Vivvo.Accounts.Scope
  alias Vivvo.Files.File, as: FileRecord

  @doc """
  Stores a file from a source path to the storage directory.

  ## Parameters
  - `from_path`: Absolute path to the source file (e.g., temp upload path)
  - `to_path`: Relative path within storage (e.g., "payments/uuid.pdf")

  ## Returns
  - `{:ok, relative_path}` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> store_file("/tmp/upload_123", "payments/abc123.pdf")
      {:ok, "payments/abc123.pdf"}
  """
  @spec store_file(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def store_file(from_path, to_path) do
    dest_path = Path.join(storage_root(), to_path)

    # Ensure the full directory path exists
    File.mkdir_p!(Path.dirname(dest_path))

    case File.cp(from_path, dest_path) do
      :ok -> {:ok, to_path}
      {:error, reason} -> {:error, "Failed to store file: #{inspect(reason)}"}
    end
  end

  @doc """
  Reads the binary content of a stored file from the storage abstraction.

  Returns {:ok, binary_data} on success, {:error, reason} on failure.
  The storage implementation is abstracted - could be local filesystem, S3, etc.

  ## Examples

      iex> read_from_storage(%FileRecord{path: "payments/abc123.pdf"})
      {:ok, <<binary_data>>}

      iex> read_from_storage(%FileRecord{path: "nonexistent.pdf"})
      {:error, :enoent}
  """
  @spec read_from_storage(FileRecord.t()) :: {:ok, binary()} | {:error, atom()}
  def read_from_storage(%FileRecord{} = file) do
    full_path = Path.join(storage_root(), file.path)
    File.read(full_path)
  end

  @doc """
  Deletes a file from storage at the given relative path.
  """
  @spec delete_stored_file(String.t()) :: :ok | {:error, atom()}
  def delete_stored_file(relative_path) do
    full_path = Path.join(storage_root(), relative_path)

    case File.rm(full_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns the absolute path to the storage root directory.

  ## Examples

      iex> storage_root()
      "/path/to/project/uploads"
  """
  @spec storage_root() :: String.t()
  def storage_root, do: Path.join(File.cwd!(), "uploads")

  @doc """
  Generates a storage file path for storing a file.

  ## Parameters
  - `subdirectory`: The subdirectory within storage (e.g., "payments")
  - `extension`: The file extension (e.g., "pdf")

  ## Returns
  A relative path like "payments/uuid.pdf"

  ## Examples

      iex> generate_storage_file_path("payments", "pdf")
      "payments/a1b2c3d4.pdf"
  """
  @spec generate_storage_file_path(String.t(), String.t()) :: String.t()
  def generate_storage_file_path(subdirectory, extension) do
    uuid = Ecto.UUID.generate()
    Path.join(subdirectory, "#{uuid}.#{extension}")
  end

  @doc """
  Stores multiple files to storage.

  ## Parameters
  - `file_mappings`: List of `{source_path, dest_relative_path}` tuples

  ## Returns
  - `{:ok, list_of_relative_paths}` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> store_files([{"/tmp/upload_123", "payments/abc123.pdf"}, {"/tmp/upload_456", "payments/def456.jpg"}])
      {:ok, ["payments/abc123.pdf", "payments/def456.jpg"]}
  """
  @spec store_files([{String.t(), String.t()}]) :: {:ok, [String.t()]} | {:error, String.t()}
  def store_files(file_mappings) when is_list(file_mappings) do
    Enum.reduce_while(file_mappings, {:ok, []}, fn {source_path, dest_path}, {:ok, acc} ->
      case store_file(source_path, dest_path) do
        {:ok, stored_path} -> {:cont, {:ok, [stored_path | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Returns the list of files for a payment.

  ## Examples

      iex> list_files_for_payment(scope, payment_id)
      [%File{}, ...]

  """
  def list_files_for_payment(%Scope{} = scope, payment_id) do
    FileRecord
    |> where([f], f.payment_id == ^payment_id and f.user_id == ^scope.user.id)
    |> Repo.all()
  end

  @doc """
  Gets a single file with expanded accessibility checks.

  Returns the file if:
  - The user in scope is the file owner (file.user_id == scope.user.id), OR
  - The user in scope is the owner of the contract associated with the file's payment
    (file.payment.contract.user_id == scope.user.id)

  Returns `nil` if the file doesn't exist or the user doesn't have access.

  ## Examples

      iex> get_file(scope, 123)
      %File{}

      iex> get_file(scope, 456)
      nil

  """
  @spec get_file(Scope.t(), integer()) :: FileRecord.t() | nil
  def get_file(%Scope{} = scope, id) do
    from(f in FileRecord,
      where: f.id == ^id,
      left_join: p in assoc(f, :payment),
      left_join: c in assoc(p, :contract),
      where: f.user_id == ^scope.user.id or c.user_id == ^scope.user.id
    )
    |> Repo.one()
  end

  @doc """
  Creates a file.

  ## Examples

      iex> create_file(scope, %{field: value})
      {:ok, %File{}}

      iex> create_file(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_file(%Scope{} = scope, attrs) do
    attrs = Map.put(attrs, "user_id", scope.user.id)

    %FileRecord{}
    |> FileRecord.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes a file.

  ## Examples

      iex> delete_file(scope, file)
      {:ok, %File{}}

      iex> delete_file(scope, file)
      {:error, %Ecto.Changeset{}}

  """
  def delete_file(%Scope{} = scope, %FileRecord{} = file) do
    if file.user_id == scope.user.id do
      # Delete the physical file first
      with :ok <- delete_stored_file(file.path) do
        # Delete database record
        Repo.delete(file)
      end
    else
      {:error, :unauthorized}
    end
  end
end
