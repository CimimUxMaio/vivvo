defmodule VivvoWeb.UploadHelpers do
  @moduledoc """
  Helper functions for handling LiveView file uploads.
  """

  @default_temp_root "tmp"
  @uploads_dir "uploads"

  @doc """
  Processes an upload entry and stores it to a temporary directory.

  This function is intended for use as a callback with `consume_uploaded_entries/3`.
  The callback receives `(meta, entry)` where `meta` is a map containing the `:path`
  and `entry` is the `%Phoenix.LiveView.UploadEntry{}` struct.

  ## Options

    * `:subdir` - Custom subdirectory within <temp_dir>/uploads/ (default: ".")

  ## Examples

      # Default: stores to <temp_dir>/uploads/
      consume_uploaded_entries(socket, :files, &process_upload_entry/2)

      # Custom subdir: stores to <temp_dir>/uploads/invoices/
      consume_uploaded_entries(socket, :files, &process_upload_entry(&1, &2, subdir: "invoices"))

  """

  @spec process_upload_entry(map(), Phoenix.LiveView.UploadEntry.t(), keyword()) ::
          {:ok, %{path: String.t(), filename: String.t()}}
  def process_upload_entry(%{path: path}, entry, opts \\ []) do
    temp_dir = build_uploads_path(opts[:subdir])
    dest = Path.join(temp_dir, Path.basename(path))

    File.mkdir_p!(temp_dir)
    File.cp!(path, dest)

    {:ok, %{path: dest, filename: entry.client_name}}
  end

  @doc """
  Consumes uploaded entries and stores them to a temporary directory.

  This is a convenience wrapper around `consume_uploaded_entries/3` that uses
  `process_upload_entry/3` as the callback. Supports the same options.

  ## Options

    * `:subdir` - Custom subdirectory within <temp_dir>/uploads/ (default: ".")

  ## Examples

      # Default: stores to <temp_dir>/uploads/
      uploaded_files = consume_file_uploads(socket, :files)

      # Custom subdir: stores to <temp_dir>/uploads/invoices/
      uploaded_files = consume_file_uploads(socket, :files, subdir: "invoices")

  """
  @spec consume_file_uploads(Phoenix.LiveView.Socket.t(), atom(), keyword()) ::
          list(%{path: String.t(), filename: String.t()})
  def consume_file_uploads(socket, name, opts \\ []) do
    Phoenix.LiveView.consume_uploaded_entries(socket, name, fn meta, entry ->
      process_upload_entry(meta, entry, opts)
    end)
  end

  defp build_uploads_path(custom_subdir) do
    root_temp = Application.get_env(:vivvo, :temp_dir) || @default_temp_root
    uploads_base = Path.join(root_temp, @uploads_dir)
    subdir = custom_subdir || "."

    Path.join(uploads_base, subdir)
  end

  @doc """
  Clears uploaded files from the temporary directory.

  Takes a list of file maps (each with a `:path` key) and deletes the
  corresponding files from the filesystem. Returns `:ok` regardless of
  individual file deletion results.

  ## Examples

      uploaded_files = [%{path: "/tmp/uploads/file1.pdf", filename: "file1.pdf"}]
      :ok = clear_upload_files(uploaded_files)

  """
  @spec clear_upload_files(list(%{path: String.t()})) :: :ok
  def clear_upload_files(uploaded_files) when is_list(uploaded_files) do
    Enum.each(uploaded_files, fn %{path: path} ->
      File.rm(path)
    end)

    :ok
  end
end
