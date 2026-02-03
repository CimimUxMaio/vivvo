defmodule Vivvo.Repo do
  use Ecto.Repo,
    otp_app: :vivvo,
    adapter: Ecto.Adapters.Postgres
end
