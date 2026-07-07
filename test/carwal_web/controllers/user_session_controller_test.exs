defmodule CarWalWeb.UserSessionControllerTest do
  use CarWalWeb.ConnCase, async: true

  import CarWal.AccountsFixtures
  alias CarWal.Accounts

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture()}
  end

  describe "POST /users/log-in - magic link" do
    test "logs the user in", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the nav (Layouts.app shell)
      conn = get(conn, ~p"/users/settings")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log-out"
    end

    test "confirms unconfirmed user", %{conn: conn, unconfirmed_user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)
      refute user.confirmed_at

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Konto erfolgreich bestätigt."

      assert Accounts.get_user!(user.id).confirmed_at

      # Now do a logged in request and assert on the nav (Layouts.app shell)
      conn = get(conn, ~p"/users/settings")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log-out"
    end

    test "redirects to login page when magic link is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => "invalid"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Der Link ist ungültig oder abgelaufen."

      assert redirected_to(conn) == ~p"/users/log-in"
      refute get_session(conn, :user_token)
    end

    test "redirects (no 500) when the token is not even base64url", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => "not base64url!"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Der Link ist ungültig oder abgelaufen."

      assert redirected_to(conn) == ~p"/users/log-in"
      refute get_session(conn, :user_token)
    end

    test "writes the long-lived remember-me cookie on the confirm POST", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      # user[remember_me] is what the confirmation form's submit button carries
      # (LiveView re-injects the submitter value before the native re-submit).
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token, "remember_me" => "true"}
        })

      assert get_session(conn, :user_token)
      assert %{max_age: max_age} = conn.resp_cookies["_car_wal_web_user_remember_me"]
      assert max_age == 3650 * 24 * 60 * 60
    end
  end

  describe "POST /users/log-in - no-JS fallback" do
    test "requests a magic link for a seeded email and redirects", %{conn: conn, user: user} do
      conn = post(conn, ~p"/users/log-in", %{"user" => %{"email" => user.email}})

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Wenn deine E-Mail-Adresse hinterlegt ist"

      assert CarWal.Repo.get_by!(CarWal.Accounts.UserToken,
               user_id: user.id,
               context: "login"
             )
    end

    test "responds identically for an unseeded email and creates nothing", %{conn: conn} do
      conn = post(conn, ~p"/users/log-in", %{"user" => %{"email" => "nobody@example.com"}})

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Wenn deine E-Mail-Adresse hinterlegt ist"

      refute get_session(conn, :user_token)
    end

    test "redirects to login for a POST without token or email", %{conn: conn} do
      conn = post(conn, ~p"/users/log-in", %{})
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Erfolgreich abgemeldet"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Erfolgreich abgemeldet"
    end
  end
end
