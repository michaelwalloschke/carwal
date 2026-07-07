defmodule CarWalWeb.AuthGuaranteesTest do
  @moduledoc """
  Story 1.2 security guarantees that the generated phx.gen.auth suite does not
  cover: no sign-up path (AC2) and an effectively-never-expiring session (AC1).
  The identical-flash / no-disclosure behaviour is covered by the generated
  login test; here we assert the DB-observable side effects.
  """
  use CarWalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CarWal.AccountsFixtures

  alias CarWal.Accounts
  alias CarWal.Accounts.{User, UserToken}
  alias CarWal.Repo

  describe "login page smoke" do
    test "renders the magic-link form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")
      assert has_element?(lv, "#login_form_magic")
    end
  end

  describe "AC2: seeded-only, no sign-up, no enumeration" do
    test "a seeded email mints a login token (mail is sent)", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv
      |> form("#login_form_magic", user: %{email: user.email})
      |> render_submit()

      assert Repo.get_by(UserToken, user_id: user.id, context: "login"),
             "a seeded member should get a login token minted"
    end

    test "an unseeded email mints no token and creates no user", %{conn: conn} do
      users_before = Repo.aggregate(User, :count)
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv
      |> form("#login_form_magic", user: %{email: "stranger@example.com"})
      |> render_submit()

      assert Repo.aggregate(User, :count) == users_before, "no user may be created"

      assert Repo.aggregate(UserToken, :count) == 0,
             "no token may be minted for an unseeded email"
    end

    test "a magic-link login for an unknown token creates no user and no session" do
      users_before = Repo.aggregate(User, :count)

      assert {:error, :not_found} =
               Accounts.login_user_by_magic_link("this-is-not-a-real-magic-token")

      assert Repo.aggregate(User, :count) == users_before
    end
  end

  describe "AC1: session effectively never expires" do
    test "a session token far older than the generated 14-day limit is still valid" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      # Travel the token ~400 days into the past — well beyond the 14-day default
      # that shipped with the generator. This fails unless @session_validity_in_days
      # was actually raised; the cookie max_age alone would not save it.
      offset_user_token(token, -400, :day)

      assert {%User{id: id}, _inserted_at} = Accounts.get_user_by_session_token(token)
      assert id == user.id
    end
  end
end
