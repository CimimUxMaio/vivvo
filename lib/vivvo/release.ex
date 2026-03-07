defmodule Vivvo.Release do
  @moduledoc """
  Release tasks for database operations.

  These functions can be called from the release using:

      bin/vivvo eval "Vivvo.Release.migrate()"
      bin/vivvo eval "Vivvo.Release.rollback(Vivvo.Repo, 1)"
      bin/vivvo eval "Vivvo.Release.drop()"
      bin/vivvo eval "Vivvo.Release.create()"
      bin/vivvo rpc "Vivvo.Release.seed()"

  Or via Makefile targets:

      make db.migrate
      make db.rollback
      make db.seed
      make db.reset
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
  Drop the database, forcing disconnection of active sessions (requires PostgreSQL 13+).
  """
  def drop do
    load_app()

    for repo <- repos() do
      case repo.__adapter__().storage_down(repo.config() ++ [force_drop: true]) do
        :ok -> :ok
        {:error, :already_down} -> :ok
        {:error, error} -> raise "Could not drop database: #{inspect(error)}"
      end
    end
  end

  @doc """
  Create the database.
  """
  def create do
    load_app()

    for repo <- repos() do
      case repo.__adapter__().storage_up(repo.config()) do
        :ok -> :ok
        {:error, :already_up} -> :ok
        {:error, error} -> raise "Could not create database: #{inspect(error)}"
      end
    end
  end

  @doc """
  Run database seeds.

  Must be called via `rpc` (not `eval`) so that the already-running application's
  processes (Repo, PubSub, etc.) are available to the seeds script:

      bin/vivvo rpc "Vivvo.Release.seed()"
  """
  def seed do
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
