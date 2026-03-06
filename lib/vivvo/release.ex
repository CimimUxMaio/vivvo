defmodule Vivvo.Release do
  @moduledoc """
  Release tasks for database operations.

  These functions can be called from the release using:

      bin/vivvo eval "Vivvo.Release.migrate()"
      bin/vivvo eval "Vivvo.Release.rollback(Vivvo.Repo, 1)"
      bin/vivvo eval "Vivvo.Release.seed()"
      bin/vivvo eval "Vivvo.Release.reset()"

  Or via Makefile targets:

      make deploy.migrate
      make deploy.rollback
      make deploy.seed
      make deploy.reset
  """

  @app :vivvo

  @doc """
  Run all pending database migrations.
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Rollback the database by the given number of steps.
  """
  def rollback(repo, step) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, step: step))
  end

  @doc """
  Run database seeds.
  """
  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          run_seeds()
        end)
    end
  end

  @doc """
  Reset the database: drop, create, migrate, and seed.
  """
  def reset do
    load_app()

    for repo <- repos() do
      # Drop the database (ignore errors if it doesn't exist)
      _ = repo.__adapter__().storage_down(repo.config())

      # Create the database
      :ok = repo.__adapter__().storage_up(repo.config())

      # Run migrations
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))

      # Run seeds
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          run_seeds()
        end)
    end
  end

  defp run_seeds do
    seeds_file = Application.app_dir(@app, "priv/repo/seeds.exs")

    if File.exists?(seeds_file) do
      Code.eval_file(seeds_file)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
