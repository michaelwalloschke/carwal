defmodule CarWalWeb.PushController do
  use CarWalWeb, :controller

  alias CarWal.Notifications

  def subscribe(conn, %{"endpoint" => endpoint, "keys" => %{"p256dh" => p256dh, "auth" => auth}}) do
    case conn.assigns[:current_scope] do
      %{user: user} when not is_nil(user) ->
        case Notifications.register_subscription(conn.assigns.current_scope, endpoint, %{
               p256dh: p256dh,
               auth: auth
             }) do
          {:ok, _subscription} ->
            conn
            |> put_status(:created)
            |> json(%{ok: true})

          {:error, changeset} ->
            errors =
              Ecto.Changeset.traverse_errors(
                changeset,
                &CarWalWeb.CoreComponents.translate_error/1
              )

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{errors: errors})
        end

      _ ->
        unauthorized(conn)
    end
  end

  def subscribe(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "missing_required_fields"})
  end

  def unsubscribe(conn, %{"endpoint" => endpoint}) do
    case conn.assigns[:current_scope] do
      %{user: user} when not is_nil(user) ->
        case Notifications.unsubscribe(conn.assigns.current_scope, endpoint) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{ok: true})

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "subscription_not_found"})
        end

      _ ->
        unauthorized(conn)
    end
  end

  def unsubscribe(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "missing_required_fields"})
  end

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "unauthenticated"})
  end
end
