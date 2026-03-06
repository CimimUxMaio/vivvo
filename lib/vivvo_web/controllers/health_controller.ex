defmodule VivvoWeb.HealthController do
  use VivvoWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
