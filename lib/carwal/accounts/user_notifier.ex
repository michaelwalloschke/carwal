defmodule CarWal.Accounts.UserNotifier do
  import Swoosh.Email

  alias CarWal.Mailer
  alias CarWal.Accounts.User

  # Delivers the email using the application mailer.
  # `:from` must be an address owned by the sovereign mailbox account
  # (mailbox.org/Posteo reject foreign senders). Set via config; defaults to a
  # placeholder for dev/test.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(Application.get_env(:carwal, :mail_from, {"CarWal", "carwal@carwal.local"}))
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "CarWal: E-Mail-Adresse ändern", """

    ==============================

    Hallo #{user.email},

    du kannst deine E-Mail-Adresse über den folgenden Link ändern:

    #{url}

    Wenn du das nicht angefordert hast, ignoriere diese E-Mail bitte.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "CarWal: Dein Anmeldelink", """

    ==============================

    Hallo #{user.email},

    du kannst dich über den folgenden Link anmelden:

    #{url}

    Wenn du das nicht angefordert hast, ignoriere diese E-Mail bitte.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "CarWal: Konto bestätigen", """

    ==============================

    Hallo #{user.email},

    willkommen bei CarWal! Bestätige dein Konto und melde dich über den
    folgenden Link an:

    #{url}

    Wenn du kein Konto bei uns erwartest, ignoriere diese E-Mail bitte.

    ==============================
    """)
  end
end
