import Config

# Helper to read env variables, trimming whitespaces and treating empty strings as nil.
# Optionally takes a default value fallback.
read_env = fn name, default ->
  case String.trim(System.get_env(name, "")) do
    "" -> default
    value -> value
  end
end

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

if config_env() != :test do
  port_raw = read_env.("PORT", "4000")

  port =
    case Integer.parse(port_raw) do
      {p, ""} when p >= 1 and p <= 65535 -> p
      _ -> raise "PORT must be an integer in 1..65535, got: #{inspect(port_raw)}"
    end

  config :carwal, CarWalWeb.Endpoint, http: [port: port]
end

if config_env() == :prod do
  database_url =
    read_env.("DATABASE_URL", nil) ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  # ECTO_IPV6 requires IPv6 reachability of the DB host (leave unset in .env.prod if using Compose service names)
  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  pool_size_raw = read_env.("POOL_SIZE", "10")

  pool_size =
    case Integer.parse(pool_size_raw) do
      {size, ""} when size >= 1 -> size
      _ -> raise "POOL_SIZE must be a positive integer, got: #{inspect(pool_size_raw)}"
    end

  config :carwal, CarWal.Repo,
    # ssl: true,
    url: database_url,
    pool_size: pool_size,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    read_env.("SECRET_KEY_BASE", nil) ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host =
    read_env.("PHX_HOST", nil) ||
      raise """
      environment variable PHX_HOST is missing.
      For example: family.carwal.de or carwal.local
      """

  config :carwal, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :carwal, CarWalWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: ["https://#{host}"],
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
  # Set-but-empty env vars (SMTP_USERNAME=) must fail like missing ones.
  if smtp_user = read_env.("SMTP_USERNAME", nil) do
    smtp_pass =
      read_env.("SMTP_PASSWORD", nil) ||
        raise "SMTP_USERNAME is set but SMTP_PASSWORD is missing (or empty)"

    smtp_port_raw = read_env.("SMTP_PORT", "587")

    smtp_port =
      case Integer.parse(smtp_port_raw) do
        {port, ""} when port >= 1 and port <= 65535 -> port
        _ -> raise "SMTP_PORT must be an integer in 1..65535, got: #{inspect(smtp_port_raw)}"
      end

    smtp_host = read_env.("SMTP_HOST", "smtp.mailbox.org")

    config :carwal, CarWal.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: smtp_host,
      port: smtp_port,
      username: smtp_user,
      password: smtp_pass,
      auth: :always,
      ssl: false,
      tls: :always,
      tls_options: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: String.to_charlist(smtp_host),
        depth: 3
      ],
      retries: 2,
      # Submission relay (posteo.de:587 with auth + STARTTLS), not MTA-to-MTA
      # delivery. no_mx_lookups: true connects directly to the relay host; false
      # would MX-resolve it (e.g. posteo.de -> mx04.posteo.de inbound MX) and
      # time out, since submission is not accepted on the MX hosts.
      no_mx_lookups: true

    # mailbox.org/Posteo reject senders not owned by the account.
    config :carwal, :mail_from, {"CarWal", read_env.("MAIL_FROM", smtp_user)}
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
