# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :carwal, :scopes,
  user: [
    default: true,
    module: CarWal.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: CarWal.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :carwal,
  namespace: CarWal,
  ecto_repos: [CarWal.Repo],
  generators: [timestamp_type: :utc_datetime]

# App-level timezone: entries are stored as utc_datetime and rendered/scheduled
# in this zone (architecture spine, Consistency Conventions).
config :carwal, :timezone, "Europe/Berlin"

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# German is the default UI locale (NFR3)
config :gettext, :default_locale, "de"

# Configure the endpoint
config :carwal, CarWalWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CarWalWeb.ErrorHTML, json: CarWalWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CarWal.PubSub,
  live_view: [signing_salt: "IdNGIJcM"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :carwal, CarWal.Mailer, adapter: Swoosh.Adapters.Local

# The three login-capable family members (operator, mother, 15yo daughter).
# Placeholders only — real names/emails are injected in config/runtime.exs from
# env vars at deploy (PII stays out of git). The 9yo daughter has no mailbox and
# is NOT a login user. `priv/repo/seeds.exs` reads this list and refuses to seed
# these `@carwal.local` placeholders in :prod.
config :carwal, :family_members, [
  %{name: "Operator", email: "operator@carwal.local"},
  %{name: "Mutter", email: "mutter@carwal.local"},
  %{name: "Tochter", email: "tochter@carwal.local"}
]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  carwal: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  carwal: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Web Push configuration using ex_nudge.
# Dev/test-only VAPID keypair, not a secret — same convention as the
# dev/test `secret_key_base` below. Prod keys come from env vars (runtime.exs).
config :ex_nudge,
  vapid_subject: "mailto:operator@carwal.local",
  vapid_public_key:
    "BLqkZjqHaBrmFpYMto__xa5Pr-WENsSv9zOadMOHw_f3ZMjSL0Zcv-ouvHr-L9hwok5Bfo8gXnApA70QcH_r9J4",
  vapid_private_key: "l3GEXt6dOO4xznWgjVnymtQHs4M39MG1rkJ-cRT57bs"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
