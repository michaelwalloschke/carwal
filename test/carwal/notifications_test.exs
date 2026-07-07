defmodule CarWal.NotificationsTest do
  use CarWal.DataCase, async: true

  alias CarWal.Notifications
  alias CarWal.Notifications.PushSubscription
  import CarWal.AccountsFixtures

  describe "push_subscriptions" do
    setup do
      user = user_fixture()
      scope = user_scope_fixture(user)
      other_user = user_fixture()
      other_scope = user_scope_fixture(other_user)

      %{user: user, scope: scope, other_user: other_user, other_scope: other_scope}
    end

    test "register_subscription/3 inserts and upserts a subscription", %{scope: scope} do
      endpoint = "https://fcm.googleapis.com/push/1"
      keys = %{p256dh: "key1", auth: "auth1"}

      assert {:ok, %PushSubscription{} = sub} =
               Notifications.register_subscription(scope, endpoint, keys)

      assert sub.user_id == scope.user.id
      assert sub.endpoint == endpoint
      assert sub.p256dh == "key1"
      assert sub.auth == "auth1"

      # Re-registering same (user, endpoint) rotates/updates keys
      new_keys = %{p256dh: "key2", auth: "auth2"}

      assert {:ok, %PushSubscription{} = updated_sub} =
               Notifications.register_subscription(scope, endpoint, new_keys)

      assert updated_sub.id == sub.id
      assert updated_sub.p256dh == "key2"
      assert updated_sub.auth == "auth2"
    end

    test "coexistence of different endpoints for the same user", %{scope: scope} do
      endpoint1 = "https://fcm.googleapis.com/push/1"
      endpoint2 = "https://fcm.googleapis.com/push/2"
      keys = %{p256dh: "key", auth: "auth"}

      assert {:ok, _} = Notifications.register_subscription(scope, endpoint1, keys)
      assert {:ok, _} = Notifications.register_subscription(scope, endpoint2, keys)

      subs = Notifications.list_subscriptions_for_user(scope)
      assert length(subs) == 2
      assert Enum.any?(subs, &(&1.endpoint == endpoint1))
      assert Enum.any?(subs, &(&1.endpoint == endpoint2))
    end

    test "list_subscriptions_for_user/1 returns only the user's subscriptions", %{
      scope: scope,
      other_scope: other_scope
    } do
      endpoint = "https://fcm.googleapis.com/push/1"
      keys = %{p256dh: "key", auth: "auth"}

      assert {:ok, _} = Notifications.register_subscription(scope, endpoint, keys)
      assert {:ok, _} = Notifications.register_subscription(other_scope, endpoint, keys)

      assert [%PushSubscription{user_id: user_id}] =
               Notifications.list_subscriptions_for_user(scope)

      assert user_id == scope.user.id

      assert [%PushSubscription{user_id: other_user_id}] =
               Notifications.list_subscriptions_for_user(other_scope)

      assert other_user_id == other_scope.user.id
    end

    test "unsubscribe/2 deletes subscription and is scoped", %{
      scope: scope,
      other_scope: other_scope
    } do
      endpoint = "https://fcm.googleapis.com/push/1"
      keys = %{p256dh: "key", auth: "auth"}

      assert {:ok, sub} = Notifications.register_subscription(scope, endpoint, keys)

      # Cannot unsubscribe using another user's scope
      assert {:error, :not_found} = Notifications.unsubscribe(other_scope, endpoint)
      assert Repo.get(PushSubscription, sub.id)

      # Can unsubscribe using owner's scope
      assert {:ok, :deleted} = Notifications.unsubscribe(scope, endpoint)
      refute Repo.get(PushSubscription, sub.id)
    end

    test "unsubscribe/2 is idempotent: a second call on the same endpoint is not_found", %{
      scope: scope
    } do
      endpoint = "https://fcm.googleapis.com/push/1"
      keys = %{p256dh: "key", auth: "auth"}

      assert {:ok, _sub} = Notifications.register_subscription(scope, endpoint, keys)

      assert {:ok, :deleted} = Notifications.unsubscribe(scope, endpoint)
      assert {:error, :not_found} = Notifications.unsubscribe(scope, endpoint)
    end

    test "register_subscription/3 rejects endpoints outside the known push service allowlist", %{
      scope: scope
    } do
      keys = %{p256dh: "key", auth: "auth"}

      assert {:error, changeset} =
               Notifications.register_subscription(scope, "https://evil.example/push", keys)

      assert %{endpoint: ["must be a known push service URL"]} = errors_on(changeset)

      assert {:error, changeset} =
               Notifications.register_subscription(scope, "http://fcm.googleapis.com/push", keys)

      assert %{endpoint: ["must be a valid https URL"]} = errors_on(changeset)
    end

    test "send_test_push deletes expired subscriptions on :subscription_expired", %{scope: scope} do
      endpoint_expired = "https://fcm.googleapis.com/expired"
      endpoint_active = "https://fcm.googleapis.com/active"
      keys = %{p256dh: "key", auth: "auth"}

      assert {:ok, sub_expired} =
               Notifications.register_subscription(scope, endpoint_expired, keys)

      assert {:ok, sub_active} = Notifications.register_subscription(scope, endpoint_active, keys)

      # Thin seam: inject a fake send function
      fake_send = fn
        %ExNudge.Subscription{endpoint: ^endpoint_expired}, _payload ->
          {:error, :subscription_expired}

        %ExNudge.Subscription{endpoint: ^endpoint_active}, _payload ->
          {:ok, %{status_code: 201}}
      end

      assert {:ok, results} = Notifications.send_test_push(scope, fake_send)
      assert length(results) == 2
      assert Enum.member?(results, {:error, :subscription_expired})
      assert Enum.member?(results, {:ok, %{status_code: 201}})

      # Expired sub should be deleted, active sub should persist
      refute Repo.get(PushSubscription, sub_expired.id)
      assert Repo.get(PushSubscription, sub_active.id)
    end

    test "send_test_push_to deletes single expired subscription", %{scope: scope} do
      endpoint = "https://fcm.googleapis.com/expired"
      keys = %{p256dh: "key", auth: "auth"}

      assert {:ok, sub} = Notifications.register_subscription(scope, endpoint, keys)

      fake_send = fn _, _ -> {:error, :subscription_expired} end

      assert {:error, :subscription_expired} =
               Notifications.send_test_push_to(scope, endpoint, fake_send)

      refute Repo.get(PushSubscription, sub.id)
    end
  end
end
