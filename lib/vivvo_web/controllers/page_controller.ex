defmodule VivvoWeb.PageController do
  use VivvoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
