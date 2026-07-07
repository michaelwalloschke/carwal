defmodule CarWal.Notifications do
  @moduledoc """
  Context owning `push_subscriptions` (AD-1). Sole sender of Web Push
  (AD-7): seeded role-default routing, minimal payloads, one pipeline
  keyed `(user_id, endpoint)` per device (AD-13). Schema lands in
  Story 1.4.
  """

  import Ecto.Query

  require Logger

  alias CarWal.Repo
  alias CarWal.Notifications.PushSubscription

  @doc """
  Registers a new push subscription for the user in the given current_scope, or updates an existing one.
  """
  def register_subscription(current_scope, endpoint, keys) do
    user = current_scope.user
    p256dh = Map.get(keys, :p256dh) || Map.get(keys, "p256dh")
    auth = Map.get(keys, :auth) || Map.get(keys, "auth")

    attrs = %{
      user_id: user.id,
      endpoint: endpoint,
      p256dh: p256dh,
      auth: auth
    }

    %PushSubscription{}
    |> PushSubscription.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:p256dh, :auth, :updated_at]},
      conflict_target: [:user_id, :endpoint]
    )
  end

  @doc """
  Lists all push subscriptions for the user in the given current_scope.
  """
  def list_subscriptions_for_user(current_scope) do
    user = current_scope.user

    from(ps in PushSubscription, where: ps.user_id == ^user.id)
    |> Repo.all()
  end

  @doc """
  Unsubscribes a user in the given current_scope from push notifications on a specific endpoint.
  """
  def unsubscribe(current_scope, endpoint) do
    user = current_scope.user

    case Repo.get_by(PushSubscription, user_id: user.id, endpoint: endpoint) do
      nil -> {:error, :not_found}
      sub -> Repo.delete(sub)
    end
  end

  @doc """
  Sends a test push notification to all subscriptions of the user in the given current_scope.
  """
  def send_test_push(current_scope, send_fun \\ default_web_push_client()) do
    results =
      current_scope
      |> list_subscriptions_for_user()
      |> Enum.map(fn sub ->
        send_to_subscription(sub, "Test-Benachrichtigung von CarWal", send_fun)
      end)

    {:ok, results}
  end

  @doc """
  Sends a test push notification to a specific subscription of the user in the given current_scope.
  """
  def send_test_push_to(current_scope, endpoint, send_fun \\ default_web_push_client()) do
    user = current_scope.user

    case Repo.get_by(PushSubscription, user_id: user.id, endpoint: endpoint) do
      nil ->
        {:error, :not_found}

      sub ->
        send_to_subscription(sub, "Test-Benachrichtigung von CarWal", send_fun)
    end
  end

  # Helper to construct ExNudge subscription and execute send.
  defp send_to_subscription(sub, payload, send_fun) do
    ex_sub = %ExNudge.Subscription{
      endpoint: sub.endpoint,
      keys: %{
        p256dh: sub.p256dh,
        auth: sub.auth
      }
    }

    case send_fun.(ex_sub, payload) do
      {:ok, _response} = ok ->
        ok

      {:error, :subscription_expired} = err ->
        # Delete stale subscription
        Repo.delete!(sub)
        err

      {:error, reason} = err ->
        Logger.warning("Failed to send push notification to sub #{sub.id}: #{inspect(reason)}")
        err
    end
  end

  defp default_web_push_client do
    Application.get_env(:carwal, :web_push_client, &ExNudge.send_notification/2)
  end
end
