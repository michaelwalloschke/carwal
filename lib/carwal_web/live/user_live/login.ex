defmodule CarWalWeb.UserLive.Login do
  use CarWalWeb, :live_view

  alias CarWal.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>Anmelden</p>
            <:subtitle :if={@current_scope}>
              Zum Ausführen sensibler Aktionen musst du dich erneut anmelden.
            </:subtitle>
          </.header>
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>Der lokale Mail-Adapter ist aktiv.</p>
            <p>
              Gesendete E-Mails findest du im <.link href="/dev/mailbox" class="underline">Postfach</.link>.
            </p>
          </div>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="E-Mail"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="btn btn-primary w-full">
            Anmeldelink per E-Mail senden <span aria-hidden="true">→</span>
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form)}
  end

  @impl true
  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    # Only seeded members receive a link. The flash below is identical whether
    # or not the email is seeded, so this discloses nothing (AC2: no user
    # enumeration). No account is ever created here — there is no sign-up path.
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "Wenn deine E-Mail-Adresse hinterlegt ist, erhältst du gleich einen Anmeldelink."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:carwal, CarWal.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
