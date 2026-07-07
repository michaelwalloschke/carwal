import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/carwal start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :carwal, CarWalWeb.Endpoint, server: true
end

config :carwal, CarWalWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :carwal, CarWal.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :carwal, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :carwal, CarWalWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # Sovereign mailbox SMTP (NFR1: German provider only, never US SaaS like
  # Mailgun/SES/SendGrid). Guarded so a missing prod mailer config is a
  # controlled failure, not a silent drop (closes the 1.1-deferred "prod mailer
  # has no real adapter"). STARTTLS on 587: ssl:false, tls::always. For implicit
  # SSL on 465 use ssl:true, tls::never.
  if smtp_user = System.get_env("SMTP_USERNAME") do
    smtp_pass =
      System.get_env("SMTP_PASSWORD") ||
        raise "SMTP_USERNAME is set but SMTP_PASSWORD is missing"

    config :carwal, CarWal.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: System.get_env("SMTP_HOST", "smtp.mailbox.org"),
      port: String.to_integer(System.get_env("SMTP_PORT", "587")),
      username: smtp_user,
      password: smtp_pass,
      auth: :always,
      ssl: false,
      tls: :always,
      retries: 2,
      no_mx_lookups: false

    # mailbox.org/Posteo reject senders not owned by the account.
    config :carwal, :mail_from, {"CarWal", System.get_env("MAIL_FROM", smtp_user)}
  else
    raise """
    SMTP_USERNAME is missing. CarWal delivers magic-link mail through a sovereign
    mailbox (mailbox.org/Posteo). Set SMTP_USERNAME and SMTP_PASSWORD (optionally
    SMTP_HOST, SMTP_PORT, MAIL_FROM) before deploying.
    """
  end

  # Real family members — PII via env, never committed. Missing emails surface
  # as a controlled failure in priv/repo/seeds.exs (which refuses nil/placeholder
  # addresses in :prod).
  config :carwal, :family_members, [
    %{
      name: System.get_env("FAMILY_OPERATOR_NAME", "Operator"),
      email: System.get_env("FAMILY_OPERATOR_EMAIL")
    },
    %{
      name: System.get_env("FAMILY_MOTHER_NAME", "Mutter"),
      email: System.get_env("FAMILY_MOTHER_EMAIL")
    },
    %{
      name: System.get_env("FAMILY_DAUGHTER_NAME", "Tochter"),
      email: System.get_env("FAMILY_DAUGHTER_EMAIL")
    }
  ]

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :carwal, CarWalWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :carwal, CarWalWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :carwal, CarWal.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
