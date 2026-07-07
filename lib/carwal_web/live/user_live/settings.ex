defmodule CarWalWeb.UserLive.Settings do
  use CarWalWeb, :live_view

  # No sudo gate: FR10 says family members are never re-prompted, and this is
  # the only authenticated page. Auth comes from the router's
  # live_session :require_authenticated_user (review decision, 2026-07-07).

  require Logger

  alias CarWal.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Kontoeinstellungen
          <:subtitle>Verwalte deine E-Mail-Adresse</:subtitle>
        </.header>
      </div>

      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="E-Mail"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with="Wird geändert...">E-Mail ändern</.button>
      </.form>

      <div class="mt-8 text-center border-t border-base-300 pt-6">
        <.link
          navigate={~p"/users/push"}
          class="btn btn-outline btn-sm"
          id="link-to-push-settings"
        >
          {gettext("Push-Benachrichtigungen verwalten")}
        </.link>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "E-Mail-Adresse erfolgreich geändert.")

        {:error, _} ->
          put_flash(socket, :error, "Der Bestätigungslink ist ungültig oder abgelaufen.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)

    {:ok, assign(socket, :email_form, to_form(email_changeset))}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        deliver_result =
          Accounts.deliver_user_update_email_instructions(
            Ecto.Changeset.apply_action!(changeset, :insert),
            user.email,
            &url(~p"/users/settings/confirm-email/#{&1}")
          )

        case deliver_result do
          {:ok, _mail} ->
            info = "Ein Bestätigungslink wurde an die neue Adresse gesendet."
            {:noreply, put_flash(socket, :info, info)}

          {:error, reason} ->
            Logger.error(
              "email-change confirmation delivery failed for user #{user.id}: #{inspect(reason)}"
            )

            {:noreply,
             put_flash(
               socket,
               :error,
               "Die Bestätigungs-E-Mail konnte nicht gesendet werden. Bitte versuche es später erneut."
             )}
        end

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end
end
