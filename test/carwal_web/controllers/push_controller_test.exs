defmodule CarWalWeb.PushControllerTest do
  use CarWalWeb.ConnCase, async: true

  alias CarWal.Notifications

  setup :register_and_log_in_user

  describe "POST /push/subscribe" do
    test "subscribes successfully with valid parameters", %{conn: conn, scope: scope} do
      # Fetch a valid CSRF token
      conn = get(conn, ~p"/")
      csrf_token = Plug.CSRFProtection.get_csrf_token()

      params = %{
        "endpoint" => "https://fcm.googleapis.com/push/123",
        "keys" => %{
          "p256dh" => "my_p256dh_key",
          "auth" => "my_auth_key"
        }
      }

      conn =
        recycle(conn)
        |> put_req_header("x-csrf-token", csrf_token)
        |> post(~p"/push/subscribe", params)

      assert json_response(conn, 201) == %{"ok" => true}

      # Verify it is in database
      [sub] = Notifications.list_subscriptions_for_user(scope)
      assert sub.endpoint == "https://fcm.googleapis.com/push/123"
      assert sub.p256dh == "my_p256dh_key"
      assert sub.auth == "my_auth_key"
    end

    test "returns 422 for missing or invalid parameters", %{conn: conn} do
      conn = get(conn, ~p"/")
      csrf_token = Plug.CSRFProtection.get_csrf_token()

      # Missing keys
      conn_missing_keys =
        recycle(conn)
        |> put_req_header("x-csrf-token", csrf_token)
        |> post(~p"/push/subscribe", %{"endpoint" => "https://fcm.googleapis.com/push/123"})

      assert json_response(conn_missing_keys, 422) == %{"error" => "missing_required_fields"}
    end

    test "returns 401 when not authenticated" do
      # Create an unauthenticated connection
      conn = build_conn()
      conn = get(conn, ~p"/")
      csrf_token = Plug.CSRFProtection.get_csrf_token()

      params = %{
        "endpoint" => "https://fcm.googleapis.com/push/123",
        "keys" => %{
          "p256dh" => "my_p256dh_key",
          "auth" => "my_auth_key"
        }
      }

      conn =
        recycle(conn)
        |> put_req_header("x-csrf-token", csrf_token)
        |> post(~p"/push/subscribe", params)

      assert json_response(conn, 401) == %{"error" => "unauthenticated"}
    end

    test "returns forbidden / throws CSRF error when CSRF token is missing", %{conn: conn} do
      params = %{
        "endpoint" => "https://fcm.googleapis.com/push/123",
        "keys" => %{
          "p256dh" => "my_p256dh_key",
          "auth" => "my_auth_key"
        }
      }

      # Run a GET request first to populate session with CSRF info
      conn = get(conn, ~p"/")

      # Recycle and force CSRF validation by removing the test skip flag
      recycled_conn =
        recycle(conn)
        |> Map.update!(:private, &Map.delete(&1, :plug_skip_csrf_protection))

      # Now do a POST without the token, which should fail
      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        post(recycled_conn, ~p"/push/subscribe", params)
      end
    end
  end

  describe "POST /push/unsubscribe" do
    setup %{scope: scope} do
      {:ok, sub} =
        Notifications.register_subscription(
          scope,
          "https://fcm.googleapis.com/push/123",
          %{p256dh: "key", auth: "auth"}
        )

      %{sub: sub}
    end

    test "unsubscribes successfully", %{conn: conn, scope: scope, sub: sub} do
      conn = get(conn, ~p"/")
      csrf_token = Plug.CSRFProtection.get_csrf_token()

      conn =
        recycle(conn)
        |> put_req_header("x-csrf-token", csrf_token)
        |> post(~p"/push/unsubscribe", %{"endpoint" => sub.endpoint})

      assert json_response(conn, 200) == %{"ok" => true}
      assert Notifications.list_subscriptions_for_user(scope) == []
    end

    test "returns 404 when subscription not found", %{conn: conn} do
      conn = get(conn, ~p"/")
      csrf_token = Plug.CSRFProtection.get_csrf_token()

      conn =
        recycle(conn)
        |> put_req_header("x-csrf-token", csrf_token)
        |> post(~p"/push/unsubscribe", %{"endpoint" => "https://fcm.googleapis.com/nonexistent"})

      assert json_response(conn, 404) == %{"error" => "subscription_not_found"}
    end

    test "returns 401 when unauthenticated", %{sub: sub} do
      conn = build_conn()
      conn = get(conn, ~p"/")
      csrf_token = Plug.CSRFProtection.get_csrf_token()

      conn =
        recycle(conn)
        |> put_req_header("x-csrf-token", csrf_token)
        |> post(~p"/push/unsubscribe", %{"endpoint" => sub.endpoint})

      assert json_response(conn, 401) == %{"error" => "unauthenticated"}
    end
  end
end
