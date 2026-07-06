defmodule CarWal.Repo do
  use Ecto.Repo,
    otp_app: :carwal,
    adapter: Ecto.Adapters.Postgres
end
