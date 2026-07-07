defmodule CarWal.SeedsTest do
  @moduledoc "Story 1.2 AC1: the seed creates exactly the three login members and is idempotent."
  use CarWal.DataCase, async: false

  import ExUnit.CaptureIO

  alias CarWal.Accounts.User
  alias CarWal.Repo

  @seeds Path.expand("../../priv/repo/seeds.exs", __DIR__)

  defp run_seeds do
    # seeds print to stdout (IO.puts) and warn to stderr (IO.warn) — swallow both.
    capture_io(:stderr, fn -> capture_io(fn -> Code.eval_file(@seeds) end) end)
  end

  test "creates exactly three users from config and is idempotent" do
    run_seeds()
    assert Repo.aggregate(User, :count) == 3

    # Re-running must not duplicate rows or raise.
    run_seeds()
    assert Repo.aggregate(User, :count) == 3
  end

  test "refuses to seed placeholder addresses when a real mail adapter is configured" do
    original_mailer = Application.get_env(:carwal, CarWal.Mailer)
    original_members = Application.get_env(:carwal, :family_members)

    on_exit(fn ->
      Application.put_env(:carwal, CarWal.Mailer, original_mailer)
      Application.put_env(:carwal, :family_members, original_members)
    end)

    # Simulate prod: a real SMTP adapter + a leftover @carwal.local placeholder.
    Application.put_env(:carwal, CarWal.Mailer, adapter: Swoosh.Adapters.SMTP)
    Application.put_env(:carwal, :family_members, [%{name: "Op", email: "op@carwal.local"}])

    assert_raise RuntimeError, ~r/Refusing to seed/, fn -> Code.eval_file(@seeds) end
    assert Repo.aggregate(User, :count) == 0, "no user may be seeded when the guard fires"
  end
end
