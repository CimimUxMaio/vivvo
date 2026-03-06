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
    start_app()
    run_seeds()
  end

  @doc """
  Reset the database: drop, create, migrate, and seed.
  """
  def reset do
    load_app()

    for repo <- repos() do
      # Drop the database, forcing disconnection of active sessions (requires PostgreSQL 13+)
      case repo.__adapter__().storage_down(repo.config() ++ [force_drop: true]) do
        :ok -> :ok
        {:error, :already_down} -> :ok
        {:error, error} -> raise "Could not drop database: #{inspect(error)}"
      end

      # Create the database
      case repo.__adapter__().storage_up(repo.config()) do
        :ok -> :ok
        {:error, :already_up} -> :ok
        {:error, error} -> raise "Could not create database: #{inspect(error)}"
      end

      # Run migrations
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    # Start the full application (Repo, PubSub, etc.) before running seeds,
    # since seeds use context functions that broadcast through PubSub
    start_app()
    run_seeds()
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

  defp start_app do
    Application.ensure_all_started(@app)
  end
end
