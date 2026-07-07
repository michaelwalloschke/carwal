defmodule CarWalWeb.UserSessionController do
  use CarWalWeb, :controller

  alias CarWal.Accounts
  alias CarWalWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "Konto erfolgreich bestätigt.")
  end

  def create(conn, params) do
    create(conn, params, "Willkommen zurück!")
  end

  # magic link login — the only login path (CarWal is passwordless, FR10)
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      _ ->
        conn
        |> put_flash(:error, "Der Link ist ungültig oder abgelaufen.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Erfolgreich abgemeldet.")
    |> UserAuth.log_out_user()
  end
end
