defmodule CarWal.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :carwal

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def seed do
    load_app()

    # Pattern-match the with_repo tuple (like migrate/rollback) so a repo-start
    # failure or a raise inside seeds.exs fails the eval non-zero instead of
    # returning {:error, _} and exiting 0 (operator would believe the family
    # was seeded when it was not).
    {:ok, _, _} =
      Ecto.Migrator.with_repo(CarWal.Repo, fn _ ->
        Code.eval_file(Path.join([:code.priv_dir(:carwal), "repo", "seeds.exs"]))
      end)
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
