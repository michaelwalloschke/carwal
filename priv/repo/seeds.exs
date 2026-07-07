# Seeds the login-capable family members (operator, mother, 15yo daughter).
# Run with: mix run priv/repo/seeds.exs
#
# The list comes from `config :carwal, :family_members`. In dev/test that's the
# `@carwal.local` placeholders from config/config.exs; in prod it's real emails
# injected from FAMILY_*_EMAIL env vars in config/runtime.exs. The 9yo daughter
# has no mailbox and is NOT a login user (future tracked-person concept, Epic 2).
#
# `users` has no name column yet (nothing in Story 1.2 reads a name), so only
# email is persisted; the config `:name` is an operator-facing label until a
# name is actually shown in the UI.

alias CarWal.Accounts

members = Application.get_env(:carwal, :family_members, [])

if members == [] do
  raise "config :carwal, :family_members is empty — nothing to seed."
end

# A real mail adapter (SMTP) means real magic links will be sent, so refuse to
# seed unreachable placeholder/missing addresses. Dev/test use Local/Test.
adapter = Application.get_env(:carwal, CarWal.Mailer)[:adapter]
real_mail? = adapter not in [Swoosh.Adapters.Local, Swoosh.Adapters.Test]

placeholder? = fn
  nil -> true
  email -> String.ends_with?(email, "@carwal.local")
end

if real_mail? and Enum.any?(members, &placeholder?.(&1.email)) do
  raise """
  Refusing to seed placeholder or missing email addresses while a real mail
  adapter (#{inspect(adapter)}) is configured. Set FAMILY_OPERATOR_EMAIL,
  FAMILY_MOTHER_EMAIL and FAMILY_DAUGHTER_EMAIL to the real member addresses
  before seeding in production.
  """
end

for %{email: email} <- members, not is_nil(email) do
  case Accounts.get_user_by_email(email) do
    nil ->
      {:ok, _user} = Accounts.register_user(%{email: email})
      IO.puts("seeded #{email}")

    _user ->
      IO.puts("exists #{email} (skipped)")
  end
end

if not real_mail? and Enum.any?(members, &placeholder?.(&1.email)) do
  IO.puts(:stderr, [
    IO.ANSI.yellow(),
    "warning: seeded @carwal.local placeholder members (dev/test). Set ",
    "FAMILY_*_EMAIL to real addresses before deploying to production.",
    IO.ANSI.reset()
  ])
end
