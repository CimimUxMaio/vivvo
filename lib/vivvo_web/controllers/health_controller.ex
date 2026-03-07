defmodule VivvoWeb.HealthController do
  use VivvoWeb, :controller

  def index(conn, _params) do
    case Vivvo.Repo.query("SELECT 1") do
      {:ok, _} ->
        json(conn, %{status: "ok"})

      {:error, _} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "error", reason: "database unavailable"})
    end
  end
end
