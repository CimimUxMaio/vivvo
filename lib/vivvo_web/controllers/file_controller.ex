defmodule VivvoWeb.FileController do
  @moduledoc """
  Controller for serving attached files to authenticated users.
  """

  use VivvoWeb, :controller

  alias Vivvo.Files

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope

    case Files.get_file(scope, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, "File not found")
        |> redirect(to: ~p"/")

      file ->
        case Files.read_from_storage(file) do
          {:ok, data} ->
            conn
            |> put_resp_content_type(content_type(file.label))
            |> send_download({:binary, data},
              filename: file.label,
              disposition: :inline
            )

          {:error, _reason} ->
            conn
            |> put_flash(:error, "Failed to read file")
            |> redirect(to: ~p"/")
        end
    end
  end

  defp content_type(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".pdf" -> "application/pdf"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".bmp" -> "image/bmp"
      ".webp" -> "image/webp"
      _ -> "application/octet-stream"
    end
  end
end
