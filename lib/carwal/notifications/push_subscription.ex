defmodule CarWal.Notifications.PushSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  schema "push_subscriptions" do
    field :endpoint, :string
    field :p256dh, :string
    field :auth, :string
    belongs_to :user, CarWal.Accounts.User

    timestamps(type: :utc_datetime)
  end

  # ponytail: allowlist by host suffix (not a full URL scanner) — covers the
  # push services the story targets (FCM/Mozilla/Windows/Apple). Extend the
  # list if a browser vendor introduces a new push service host.
  @allowed_endpoint_host_suffixes ~w(
    .googleapis.com
    .mozilla.com
    .notify.windows.com
    .push.apple.com
  )

  @doc false
  def changeset(push_subscription, attrs) do
    push_subscription
    |> cast(attrs, [:user_id, :endpoint, :p256dh, :auth])
    |> validate_required([:user_id, :endpoint, :p256dh, :auth])
    |> validate_change(:endpoint, &validate_push_service_url/2)
  end

  # Blocks SSRF: without this, any client-supplied endpoint would later be
  # POSTed to by the server (Notifications.send_to_subscription/3).
  defp validate_push_service_url(:endpoint, endpoint) do
    case URI.parse(endpoint) do
      %URI{scheme: "https", host: host} when is_binary(host) ->
        if Enum.any?(@allowed_endpoint_host_suffixes, &String.ends_with?(host, &1)) do
          []
        else
          [endpoint: "must be a known push service URL"]
        end

      _ ->
        [endpoint: "must be a valid https URL"]
    end
  end
end
