defmodule Vivvo.FilesTest do
  use Vivvo.DataCase

  alias Vivvo.Files

  describe "files" do
    alias Vivvo.Files.File

    import Vivvo.AccountsFixtures, only: [user_scope_fixture: 0]
    import Vivvo.FilesFixtures

    @invalid_attrs %{"label" => nil, "path" => nil}

    test "list_files_for_payment/2 returns all files for a payment" do
      scope = user_scope_fixture()
      file = file_fixture(scope)
      assert Files.list_files_for_payment(scope, file.payment_id) == [file]
    end

    test "get_file/2 returns the file with given id" do
      scope = user_scope_fixture()
      file = file_fixture(scope)
      other_scope = user_scope_fixture()
      assert Files.get_file(scope, file.id) == file
      assert Files.get_file(other_scope, file.id) == nil
    end

    test "create_file/2 with valid data creates a file" do
      scope = user_scope_fixture()
      payment = Vivvo.PaymentsFixtures.payment_fixture(scope)

      valid_attrs = %{
        "label" => "receipt.pdf",
        "path" => "uploads/payments/test-file.pdf",
        "payment_id" => payment.id
      }

      assert {:ok, %File{} = file} = Files.create_file(scope, valid_attrs)
      assert file.label == "receipt.pdf"
      assert file.path == "uploads/payments/test-file.pdf"
      assert file.user_id == scope.user.id
    end

    test "create_file/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Files.create_file(scope, @invalid_attrs)
    end

    test "create_file/2 rejects invalid file extensions" do
      scope = user_scope_fixture()
      payment = Vivvo.PaymentsFixtures.payment_fixture(scope)

      invalid_attrs = %{
        "label" => "malicious.exe",
        "path" => "uploads/payments/test-file.exe",
        "payment_id" => payment.id
      }

      assert {:error, %Ecto.Changeset{}} = Files.create_file(scope, invalid_attrs)
    end

    test "delete_file/2 deletes the file" do
      scope = user_scope_fixture()
      file = file_fixture(scope)
      assert {:ok, %File{}} = Files.delete_file(scope, file)
      assert Files.get_file(scope, file.id) == nil
    end

    test "delete_file/2 with invalid scope returns unauthorized" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      file = file_fixture(scope)
      assert {:error, :unauthorized} = Files.delete_file(other_scope, file)
    end

    test "store_files/1 stores multiple files with explicit destinations" do
      # Create temp files to test with
      temp_path1 = Path.join(System.tmp_dir!(), "test_file_#{System.unique_integer()}.pdf")
      temp_path2 = Path.join(System.tmp_dir!(), "test_file_#{System.unique_integer()}.jpg")
      Elixir.File.write!(temp_path1, "test content 1")
      Elixir.File.write!(temp_path2, "test content 2")

      dest_path1 = "payments/#{Ecto.UUID.generate()}.pdf"
      dest_path2 = "payments/#{Ecto.UUID.generate()}.jpg"

      file_mappings = [{temp_path1, dest_path1}, {temp_path2, dest_path2}]

      assert {:ok, stored_paths} = Files.store_files(file_mappings)
      assert length(stored_paths) == 2
      assert dest_path1 in stored_paths
      assert dest_path2 in stored_paths

      # Verify files exist
      Enum.each(stored_paths, fn path ->
        full_path = Path.join(Files.storage_root(), path)
        assert Elixir.File.exists?(full_path)
      end)

      # Cleanup
      Enum.each(stored_paths, fn path ->
        full_path = Path.join(Files.storage_root(), path)
        Elixir.File.rm(full_path)
      end)

      Elixir.File.rm(temp_path1)
      Elixir.File.rm(temp_path2)
    end

    test "store_files/1 returns empty list for empty input" do
      assert {:ok, []} = Files.store_files([])
    end

    test "store_files/1 returns error on failure" do
      # Try to store a non-existent file
      nonexistent_path = "/nonexistent/path/to/file.pdf"
      dest_path = "payments/test.pdf"

      assert {:error, _reason} = Files.store_files([{nonexistent_path, dest_path}])
    end
  end

  describe "generate_storage_file_path/2" do
    test "generates storage path with subdirectory and extension" do
      path = Files.generate_storage_file_path("payments", "pdf")
      assert String.starts_with?(path, "payments/")
      assert String.ends_with?(path, ".pdf")
      # Should be in format: payments/uuid.pdf
      assert path =~ ~r/^payments\/[a-f0-9-]+\.pdf$/
    end

    test "generates unique paths on each call" do
      path1 = Files.generate_storage_file_path("docs", "txt")
      path2 = Files.generate_storage_file_path("docs", "txt")
      refute path1 == path2
    end
  end

  describe "storage_root/0" do
    test "returns absolute path to uploads directory" do
      root = Files.storage_root()
      assert String.ends_with?(root, "/uploads")
      assert File.dir?(root) || !File.exists?(root)
    end
  end

  describe "store_file/2" do
    test "stores file from source to destination" do
      # Create temp file
      temp_path = Path.join(System.tmp_dir!(), "test_#{System.unique_integer()}.txt")
      File.write!(temp_path, "test content")

      relative_path = "test/#{Ecto.UUID.generate()}.txt"

      assert {:ok, ^relative_path} = Files.store_file(temp_path, relative_path)

      # Verify file exists
      full_path = Path.join(Files.storage_root(), relative_path)
      assert File.exists?(full_path)
      assert File.read!(full_path) == "test content"

      # Cleanup
      File.rm!(temp_path)
      File.rm!(full_path)
    end

    test "returns error when source file doesn't exist" do
      relative_path = "test/#{Ecto.UUID.generate()}.txt"

      assert {:error, _} = Files.store_file("/nonexistent/path.txt", relative_path)
    end
  end

  describe "delete_stored_file/1" do
    test "deletes file at relative path" do
      # Create test file
      relative_path = "test/#{Ecto.UUID.generate()}.txt"
      full_path = Path.join(Files.storage_root(), relative_path)
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, "test content")

      assert :ok = Files.delete_stored_file(relative_path)
      refute File.exists?(full_path)
    end

    test "returns ok when file doesn't exist" do
      relative_path = "test/nonexistent_#{System.unique_integer()}.txt"

      assert :ok = Files.delete_stored_file(relative_path)
    end
  end
end
