defmodule CarWalWeb.UserLive.PushSettings do
  use CarWalWeb, :live_view

  alias CarWal.Notifications

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-2xl mx-auto p-4">
        <div class="text-center mb-8">
          <.header>
            {gettext("Benachrichtigungen")}
            <:subtitle>{gettext("Verwalte Push-Benachrichtigungen für deine Geräte")}</:subtitle>
          </.header>
        </div>

        <div id="push-setup" phx-hook="Push" data-vapid-key={@vapid_public_key} class="space-y-6">
          <div class="bg-base-200 rounded-xl p-6 border border-base-300 shadow-sm">
            <h2 class="text-lg font-semibold mb-2">{gettext("Aktuelles Gerät registrieren")}</h2>
            <p class="text-sm opacity-75 mb-4">
              {gettext(
                "Registriere dieses Gerät, um Benachrichtigungen direkt auf deinen Sperrbildschirm zu erhalten."
              )}
            </p>
            <button
              id="enable-push-btn"
              class="btn btn-primary w-full sm:w-auto"
            >
              {gettext("Benachrichtigungen aktivieren")}
            </button>
          </div>

          <div class="bg-base-200 rounded-xl p-6 border border-base-300 shadow-sm">
            <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center mb-6 gap-4">
              <div>
                <h2 class="text-lg font-semibold">{gettext("Registrierte Geräte")}</h2>
                <p class="text-xs opacity-60 mt-1">
                  {gettext("Geräte, die derzeit Push-Benachrichtigungen empfangen können.")}
                </p>
              </div>
              <%= if length(@subscriptions) > 0 do %>
                <button
                  phx-click="send_test_push_all"
                  class="btn btn-secondary btn-sm w-full sm:w-auto"
                  id="test-all-devices-btn"
                >
                  {gettext("An alle Geräte senden")}
                </button>
              <% end %>
            </div>

            <%= if length(@subscriptions) == 0 do %>
              <div class="text-center py-6 border border-dashed border-base-300 rounded-lg">
                <p class="text-sm opacity-60 italic">{gettext("Keine registrierten Geräte.")}</p>
              </div>
            <% else %>
              <div class="divide-y divide-base-300">
                <%= for sub <- @subscriptions do %>
                  <div class="py-4 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
                    <div class="min-w-0 flex-1">
                      <p class="text-sm font-mono truncate opacity-80" title={sub.endpoint}>
                        {truncate_endpoint(sub.endpoint)}
                      </p>
                      <p class="text-xs opacity-50 mt-1">
                        {gettext("Registriert am")} {Calendar.strftime(
                          sub.inserted_at,
                          "%d.%m.%Y %H:%M"
                        )} Uhr
                      </p>
                    </div>
                    <div class="flex gap-2 w-full sm:w-auto">
                      <button
                        phx-click="send_test_push"
                        phx-value-endpoint={sub.endpoint}
                        class="btn btn-outline btn-sm flex-1 sm:flex-none"
                        id={"test-push-#{sub.id}"}
                      >
                        {gettext("Test-Push")}
                      </button>
                      <button
                        phx-click="unsubscribe"
                        phx-value-endpoint={sub.endpoint}
                        class="btn btn-error btn-sm flex-1 sm:flex-none"
                        id={"delete-push-#{sub.id}"}
                      >
                        {gettext("Abbestellen")}
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    current_scope = socket.assigns.current_scope
    subscriptions = Notifications.list_subscriptions_for_user(current_scope)
    vapid_public_key = Application.get_env(:ex_nudge, :vapid_public_key)

    {:ok,
     socket
     |> assign(:subscriptions, subscriptions)
     |> assign(:vapid_public_key, vapid_public_key)}
  end

  @impl true
  def handle_event("send_test_push", %{"endpoint" => endpoint}, socket) do
    current_scope = socket.assigns.current_scope

    case Notifications.send_test_push_to(current_scope, endpoint) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, gettext("Test-Push wurde an das Gerät gesendet."))}

      {:error, :subscription_expired} ->
        # Refresh subscriptions list since the stale sub was deleted
        subscriptions = Notifications.list_subscriptions_for_user(current_scope)

        socket
        |> put_flash(
          :error,
          gettext("Die Registrierung dieses Geräts ist abgelaufen und wurde gelöscht.")
        )
        |> assign(:subscriptions, subscriptions)
        |> then(&{:noreply, &1})

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Fehler beim Senden des Test-Pushs."))}
    end
  end

  def handle_event("send_test_push_all", _params, socket) do
    current_scope = socket.assigns.current_scope

    {:ok, _results} = Notifications.send_test_push(current_scope)
    # Refresh in case any subscription expired and got deleted
    subscriptions = Notifications.list_subscriptions_for_user(current_scope)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Test-Push wurde an alle Geräte gesendet."))
     |> assign(:subscriptions, subscriptions)}
  end

  def handle_event("unsubscribe", %{"endpoint" => endpoint}, socket) do
    current_scope = socket.assigns.current_scope

    case Notifications.unsubscribe(current_scope, endpoint) do
      {:ok, _} ->
        subscriptions = Notifications.list_subscriptions_for_user(current_scope)

        socket
        |> put_flash(:info, gettext("Gerät erfolgreich abbestellt."))
        |> assign(:subscriptions, subscriptions)
        |> then(&{:noreply, &1})

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Fehler beim Abbestellen."))}
    end
  end

  def handle_event("push_subscribed", _params, socket) do
    current_scope = socket.assigns.current_scope
    subscriptions = Notifications.list_subscriptions_for_user(current_scope)

    socket
    |> put_flash(:info, gettext("Gerät erfolgreich für Push-Benachrichtigungen registriert."))
    |> assign(:subscriptions, subscriptions)
    |> then(&{:noreply, &1})
  end

  def handle_event("push_unsubscribed", _params, socket) do
    current_scope = socket.assigns.current_scope
    subscriptions = Notifications.list_subscriptions_for_user(current_scope)

    socket
    |> put_flash(:info, gettext("Gerät abbestellt."))
    |> assign(:subscriptions, subscriptions)
    |> then(&{:noreply, &1})
  end

  defp truncate_endpoint(nil), do: ""

  defp truncate_endpoint(endpoint) do
    case URI.parse(endpoint) do
      %URI{host: host} when is_binary(host) ->
        host <> "..." <> String.slice(endpoint, -10..-1)

      _ ->
        String.slice(endpoint, 0..30) <> "..."
    end
  end
end
