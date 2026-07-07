defmodule CarWal.Accounts do
  @moduledoc """
  Context for users and the family membership seed (AD-1).

  Passwordless magic-link auth (FR10). All data access goes through this
  context; `CarWalWeb` never touches `Repo` directly (AD-2).
  """

  import Ecto.Query, warn: false

  require Logger

  alias CarWal.Repo
  alias CarWal.Accounts.{User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `CarWal.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  CarWal is passwordless (FR10), so there are two cases:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email. They get confirmed, logged
     in, and all tokens - including session ones - are expired. In theory,
     no other tokens exist but we delete all of them for best security
     practices.

  The magic link token is only ever issued for a seeded user
  (`deliver_login_instructions/2` is called from the login LiveView only
  after `get_user_by_email/1` finds a member). An unseeded email has no
  token row, so `verify_magic_link_token_query/1` returns nothing and this
  returns `{:error, :not_found}` — no user is ever created here (AC2: no
  sign-up path).
  """
  def login_user_by_magic_link(token) do
    case UserToken.verify_magic_link_token_query(token) do
      {:ok, query} ->
        case Repo.one(query) do
          {%User{confirmed_at: nil} = user, _token} ->
            user
            |> User.confirm_changeset()
            |> update_user_and_delete_all_tokens()

          {user, token} ->
            # delete_all, not delete!: a concurrent second use of the same link
            # (double-click, two tabs) is a no-op instead of a StaleEntryError 500.
            Repo.delete_all(from(t in UserToken, where: t.id == ^token.id))
            {:ok, {user, []}}

          nil ->
            {:error, :not_found}
        end

      # the raw POST param may not even be base64url — invalid link, not a crash
      :error ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    user_token = Repo.insert!(user_token)

    case UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token)) do
      {:ok, _mail} = ok ->
        ok

      {:error, _reason} = error ->
        # a failed send must not leave a token behind that blocks the
        # request_login_link/2 throttle for the next 15 minutes
        Repo.delete_all(from(t in UserToken, where: t.id == ^user_token.id))
        error
    end
  end

  @doc """
  Requests a magic-link login mail for the given email address.

  Single entry point for the public login form (LiveView submit and the no-JS
  controller fallback). Always returns `:ok` so the response never discloses
  whether an email is seeded (AC2, FR10: no sign-up path). Delivery is gated
  on a seeded user, throttled to one unexpired link per member, and failures
  are logged — the UI must stay identical either way.
  """
  def request_login_link(email, magic_link_url_fun)
      when is_binary(email) and is_function(magic_link_url_fun, 1) do
    user = get_user_by_email(email)

    cond do
      is_nil(user) ->
        :ok

      # ponytail: throttle = one live link per member (the 15-min token window);
      # add per-IP limiting only if the app ever opens beyond the family.
      Repo.exists?(UserToken.unexpired_login_token_query(user)) ->
        :ok

      true ->
        case deliver_login_instructions(user, magic_link_url_fun) do
          {:ok, _mail} ->
            :ok

          {:error, reason} ->
            Logger.error("magic-link delivery failed for user #{user.id}: #{inspect(reason)}")
            :ok
        end
    end
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
