defmodule CarWalWeb.UserLive.PushSettingsTest do
  use CarWalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias CarWal.Notifications

  setup :register_and_log_in_user

  describe "PushSettings LiveView" do
    test "renders push settings page correctly when logged in", %{conn: conn, scope: scope} do
      {:ok, sub} =
        Notifications.register_subscription(
          scope,
          "https://fcm.googleapis.com/push/123",
          %{p256dh: "key", auth: "auth"}
        )

      {:ok, view, html} = live(conn, ~p"/users/push")

      assert html =~ "Benachrichtigungen"
      assert html =~ "Aktuelles Gerät registrieren"
      assert html =~ "Registrierte Geräte"
      assert has_element?(view, "#enable-push-btn")
      assert has_element?(view, "#test-push-#{sub.id}")
      assert has_element?(view, "#delete-push-#{sub.id}")
      assert html =~ "fcm.googleapis.com"
    end

    test "handles unsubscribe event", %{conn: conn, scope: scope} do
      {:ok, sub} =
        Notifications.register_subscription(
          scope,
          "https://fcm.googleapis.com/push/123",
          %{p256dh: "key", auth: "auth"}
        )

      {:ok, view, _html} = live(conn, ~p"/users/push")

      assert has_element?(view, "#delete-push-#{sub.id}")

      html =
        view
        |> element("#delete-push-#{sub.id}")
        |> render_click()

      assert html =~ "Gerät erfolgreich abbestellt."
      refute has_element?(view, "#delete-push-#{sub.id}")
      assert Notifications.list_subscriptions_for_user(scope) == []
    end

    test "handles send_test_push_all event", %{conn: conn, scope: scope} do
      {:ok, _sub} =
        Notifications.register_subscription(
          scope,
          "https://fcm.googleapis.com/push/123",
          %{p256dh: "key", auth: "auth"}
        )

      {:ok, view, _html} = live(conn, ~p"/users/push")

      html =
        view
        |> element("#test-all-devices-btn")
        |> render_click()

      assert html =~ "Test-Push wurde an alle Geräte gesendet."
    end

    test "handles send_test_push event for a single device", %{conn: conn, scope: scope} do
      {:ok, sub} =
        Notifications.register_subscription(
          scope,
          "https://fcm.googleapis.com/push/123",
          %{p256dh: "key", auth: "auth"}
        )

      {:ok, view, _html} = live(conn, ~p"/users/push")

      html =
        view
        |> element("#test-push-#{sub.id}")
        |> render_click()

      assert html =~ "Test-Push wurde an das Gerät gesendet."
    end
  end
end
