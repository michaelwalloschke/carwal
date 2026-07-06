# CarWal

Private family coordination app (5 members): Phoenix LiveView PWA aggregating
two German school apps (IServ, Schulmanager) via iCal + email.

## Development

Requirements: Elixir 1.20 / OTP 27+ (see `.tool-versions`), Docker.

* Start PostgreSQL 18:
  `docker run -d --name carwal-pg -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres:18`
* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

UI locale is German (gettext default `de`); times are stored UTC and rendered
in `Europe/Berlin`.

## Architecture

Binding invariants live in
`_bmad-output/planning-artifacts/architecture/architecture-carwal-2026-07-05/ARCHITECTURE-SPINE.md`.
Domain logic sits in six contexts under `lib/carwal/`: accounts, entries,
ingestion, chat, location, notifications — one owner per table, web layer
never touches the Repo.
