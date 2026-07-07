---
baseline_commit: 9979a5b1d5c4688f9fcabcf6b7c1a2787f72bf6b
---

# Story 1.2: Magic-Link Login for Seeded Members

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a family member,
I want to log in with just my email address via a magic link,
so that I never need a password and stay logged in long-term.

## Acceptance Criteria

1. **Given** a login-capable member seeded in the database (no public sign-up path exists), **when** they enter their email address on the login page, **then** a German-language magic-link email is sent via Swoosh SMTP through the sovereign mailbox **and** clicking the link creates a long-lived session (effectively never re-prompts — see Task 4). Only the three login-capable members (operator, mother, 15yo daughter) are seeded; the 9yo daughter has no mailbox and is **not** a `users` row (she enters the model as a tracked person in Epic 2+).
2. **Given** an email address that is not seeded, **when** it is submitted on the login page, **then** no email is sent **and** the UI response is byte-for-byte identical to the success case (no user enumeration), **and** even a forged/valid-looking magic-link token for an unseeded address creates **no** user and **no** session (no sign-up path — enforced in code, not merely by removing the registration form).
3. **Given** a logged-in member, **when** they navigate the app, **then** all authenticated LiveViews run in a single `live_session` with the shared layout/nav shell (AD-13) and scope-based data access (AD-2).

## Tasks / Subtasks

- [x] Task 1: Generate magic-link auth via `phx.gen.auth` (AC: 1, 3)
  - [x] Run `mix phx.gen.auth Accounts User users` (Phoenix 1.8.8 magic-link default). Accept the generator's prompts; it overwrites the bare `lib/carwal/accounts.ex` stub — **that overwrite is expected and correct** (the 1.1 stub's moduledoc says so). Namespace stays `CarWal`/`CarWalWeb` (already correct from `--module CarWal` in 1.1).
  - [x] The generator creates: `lib/carwal/accounts/{scope,user,user_token,user_notifier}.ex`, `lib/carwal_web/user_auth.ex`, `lib/carwal_web/live/user_live/{login,registration,settings,confirmation}.ex` + `.html.heex`, a migration creating `users` + `users_tokens`, `lib/carwal_web/user_session_controller.ex`, `AccountsFixtures` test helper, and wires `:scopes` config into `config/config.exs` + `fetch_current_scope_for_user` plug into the `:browser` pipeline + `:mount_current_scope` on_mount hook. Verify all of these landed; do not hand-write what the generator wrote.
  - [x] Run the generated migration: `mix ecto.migrate` (against the existing `carwal-pg` on port 5433 — do NOT recreate the DB; `users`/`users_tokens` are additive).
  - [x] Do NOT add Oban, ical, yugo, ex_nudge, mistral, or bcrypt deps. Magic-link auth has no password hashing; if the generator offers a password-hashing dep, decline — CarWal is passwordless (FR10).
- [x] Task 2: Remove the public sign-up path — routes/LiveView **and** the code path (AC: 1, AC: 2 — "no public sign-up path exists")
  - [x] Delete the generated registration **route** from `router.ex` **and** the `UserLive.Registration` module + its `.html.heex`. CarWal members are seeded by the operator, never self-registered (FR10: "invite-by-hand", "operator performs each member's first login hands-on at onboarding").
  - [x] **Keep the `Accounts` user-creation context function** (verify its generated name — 1.8 magic-link likely emits `register_user/1`, NOT `create_user/1`). The seed (Task 5) and `AccountsFixtures` + the `:register_and_log_in_user` scope-test helper depend on it. Delete the *route/LiveView*, never the context function.
  - [x] **Enforce seeded-only in code (this is the real AC2 work, not verification).** Two edits to the generated `Accounts`/login path:
    - Login: gate the magic-link delivery on `get_user_by_email/1` returning a seeded user; return the **identical** flash/response whether or not the email is seeded. Phoenix's own `phx.gen.auth` guide states the generated code does **not** protect against enumeration — so this is an active change, not a given.
    - Magic-link confirm callback (`login_user_by_magic_link`/token-confirm path): **remove any auto-registration branch** so an unknown/unconfirmed email can never be turned into a `User` + session. Read the generated confirm path before editing.
  - [x] Keep `UserLive.Login`, `UserLive.Settings`, `UserLive.Confirmation` (if generated) — login is the entry point; settings/confirmation serve the generated account flows.
  - [x] Grep for any remaining `~p"/users/register"` / `registration_path` references in templates/tests and remove them (the login page's "register" link must go).
- [x] Task 3: German magic-link email via Swoosh (AC: 1, NFR1)
  - [x] Find the generated magic-link delivery function (the `UserNotifier`/mailer call path from `Accounts.deliver_magic_link/2`-equivalent). Translate the magic-link email subject + body to German through the `Accounts.UserNotifier` module (or wherever the generator emits the email text). All user-facing strings German (NFR3).
  - [x] Add `{:gen_smtp, "~> 1.1"}` to `deps()` in `mix.exs` (required by `Swoosh.Adapters.SMTP`, not bundled by Swoosh). `mix deps.get`.
  - [x] Wire the prod mailer in `config/runtime.exs` inside the existing `if config_env() == :prod do` block, reading env vars (sovereign mailbox — mailbox.org/Posteo, NFR1; never a non-EU SaaS):
    ```elixir
    config :carwal, CarWal.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: System.get_env("SMTP_HOST", "smtp.mailbox.org"),
      port: String.to_integer(System.get_env("SMTP_PORT", "587")),
      username: System.get_env("SMTP_USERNAME"),
      password: System.get_env("SMTP_PASSWORD"),
      auth: :always,
      ssl: false,        # STARTTLS on 587; for 465 implicit SSL use ssl: true, tls: :never
      tls: :always,
      retries: 2,
      no_mx_lookups: false
    ```
    Guard with `if smtp_user = System.get_env("SMTP_USERNAME") && smtp_pass = System.get_env("SMTP_PASSWORD") do ... end` so a missing prod mailer config is a controlled failure, not a silent drop (this closes the 1.1-deferred "prod mailer has no real adapter" item). Set `:from` via `Swoosh.Email.from/2` to the authenticated mailbox address (mailbox.org/Posteo reject senders not owned by the account — use `MAIL_FROM` env or the SMTP username).
  - [x] Leave `config/config.exs` (`Swoosh.Adapters.Local`), `config/dev.exs` (dev routes + mailbox preview at `/dev/mailbox`), and `config/test.exs` (`Swoosh.Adapters.Test`) as-is — dev/test already correct from 1.1.
- [x] Task 4: Effectively-never-expiring session — **two layers must both change** (AC: 1)
  - [x] **Layer 1 (cookie):** in the generated `CarWalWeb.UserAuth`, set the remember-me / session cookie `max_age` for the magic-link login path to `3650 * 24 * 60 * 60` (~10 years, "never re-prompt" per operator). The `log_in_user/3` + cookie path is where this lands — read it before editing.
  - [x] **Layer 2 (DB token — the binding limit the cookie alone does NOT extend):** the generated `Accounts.UserToken` carries `@session_validity_in_days 60`. `fetch_current_scope_for_user` rejects any session token older than this **regardless of cookie max_age** — so cookie-only leaves a hard 60-day ceiling and AC1 fails silently ~2 months in. Bump `@session_validity_in_days` to `3650` to match Layer 1.
  - [x] Default the magic-link login to `remember_me: true` (family members should never be re-prompted). Document in Completion Notes that AC1's "~1 year" was **widened to effectively-never (~10 years)** per operator preference, and that both layers were changed.
- [x] Task 5: Seed the three login-capable members (AC: 1, AC 2 — the "seeded in the database" precondition)
  - [x] Replace the stub `priv/repo/seeds.exs` with a seed that creates the **three login-capable members** (operator, mother, 15yo daughter) via the generated `Accounts` user-creation fn (verify name — likely `register_user/1`, not `create_user/1`). **Name + email only** — no role. The 9yo daughter is **not** seeded (no mailbox, cannot magic-link; she is a future tracked-person concept, not a `users` row).
  - [x] **No `role` column.** The migration stays exactly what `phx.gen.auth` emits — zero hand-added schema. Roles/notification routing are Epic 2 (FR14); when routing lands it adds its own additive migration + re-seeds. (Reversed from an earlier draft that added a `role` enum — the enum values were factually wrong: no "father"; the operator is a person + the mother's partner, not a family role. Freezing a wrong, unread enum into a DB constraint now is exactly the trap we avoid.)
  - [x] **PII stays out of git.** Drive the list from `config :carwal, :family_members` (list of `{name, email}`). Committed `config/config.exs` holds **placeholders only** (`@carwal.local`) — real names/emails are injected at deploy via `config/runtime.exs` reading env vars (three fixed people → three env vars, no parser needed; same pattern as the Task 3 SMTP block).
  - [x] **Prod refuses placeholders.** In `:prod`, if any resolved member email is a `@carwal.local` placeholder (or the list is empty), the seed **raises/aborts** — do not seed fake, unreachable users into the real DB. In dev/test the placeholders are fine (with the existing `IO.warn`).
  - [x] Idempotent on re-seed (upsert by email, or `insert ... on_conflict: :nothing`) — re-running creates no duplicates and does not raise.
- [x] Task 6: Single authenticated `live_session` + CarWal nav shell (AC: 3, AD-13, AD-2)
  - [x] In `router.ex`, keep exactly **one** authenticated `live_session` (the generator creates `live_session :require_authenticated_user, on_mount: [{CarWalWeb.UserAuth, :ensure_authenticated}]` — use that one). All future authenticated LiveViews (Epic 2+) go inside it. Do not add a second `live_session`.
  - [x] Replace the starter-promo nav in `Layouts.app` (`lib/carwal_web/components/layouts.ex`) with a CarWal nav: logo link to `/`, theme toggle retained, and a login/logout control driven by `@current_scope` (login link to `~p"/users/log_in"` when logged out, logout button posting to `~p"/users/log_out"` when logged in). This closes the 1.1-deferred "nav shell is unmodified starter promo" item (it was deferred to "Story 1.2+ when real routes land" — they land here).
  - [x] Every generated LiveView template begins with `<Layouts.app flash={@flash} current_scope={@current_scope} ...>` (AGENTS.md: mandatory; the `current_scope` attr already exists on `Layouts.app`). Do not call `<.flash_group>` from any template (it's forbidden outside `layouts.ex`; `Layouts.app` already renders it).
  - [x] Verify the `:browser` pipeline got `plug :fetch_current_scope_for_user` (generator adds it) — AD-2 scope plumbing. Authenticated reads go through scope-taking context functions; nothing in `CarWalWeb` touches `Repo` directly (AD-2, enforced from this story on).
- [x] Task 7: Tests + verification (AC: 1, 2, 3)
  - [x] **Prune, don't keep, tests for removed behavior.** Delete the generated registration-LiveView tests and any "magic link registers/creates a new user" test — that behavior is deliberately removed (Task 2), so keeping those tests just leaves them red. **Keep** `AccountsFixtures` and the `:register_and_log_in_user` helper intact (all scope tests depend on them); keep login/settings/confirmation tests.
  - [x] Add a no-enumeration test (AC 2): POST a seeded email → a magic-link email is queued (`Swoosh.Adapters.Test` mailbox); POST an unseeded email → **no** email queued **and** the rendered response/flash is identical to the seeded case (assert same text/flash, assert mailbox empty for the unseeded submission).
  - [x] Add a no-sign-up test (AC 2): a forged/valid-looking magic-link token for an unseeded email creates **no** `User` and establishes **no** session (assert `Accounts` user count unchanged, assert no authenticated scope).
  - [x] Add a session-longevity test (AC 1): assert **both** layers — the login set-cookie `max_age` is `3650 * 24 * 60 * 60`, **and** travel a session token's `inserted_at` back ~400 days and assert the user is still authenticated (proves `@session_validity_in_days` was raised; the cookie assertion alone passes even when the real session is already broken at 60 days).
  - [x] Add a seed test: `mix run priv/repo/seeds.exs` against the test DB creates exactly **three** users with the configured emails; re-running is idempotent (no duplicate rows, no raise). (Reconcile the seed's user-creation call to the actual generated fn name.)
  - [x] Add one render smoke test for the login LiveView (one render smoke test per LiveView, per spine Testing convention) — assert `has_element?(view, "#login-form")` (or the generated form id), not raw HTML text.
  - [x] `mix precommit` (compile --warnings-as-errors, deps.unlock --unused, format, test) green. `mix test` green against `carwal-pg` on 5433. `mix ecto.reset` green (migrations + seeds replayable).
  - [x] Update `test/support/data_case.ex` `errors_on/1` docstring example: it references `Accounts.create_user/1` "which does not exist yet". The generator emits the user-creation fn under a different name (likely `register_user/1`) — point the example at the **actual** generated name, or swap to a generic changeset example; pick one, note it.

## Dev Notes

### Critical guardrails (read before coding)

- **`phx.gen.auth` overwrites `lib/carwal/accounts.ex`.** The 1.1 stub exists solely to be overwritten here — its moduledoc says so. Accept the overwrite. Do not preserve the 4-line stub. After generation, `Accounts` owns `User`, `UserToken`, `Scope`, `UserNotifier` per AD-1.
- **No public sign-up.** FR10 is explicit: "no public sign-up path exists", "operator performs each member's first login hands-on at onboarding", "invite-by-hand for 5 people". The generator's default registration LiveView + route MUST be removed (Task 2). Leaving it is a spec violation, not a convenience.
- **No-enumeration + no-sign-up is active code, NOT a freebie from the generator.** Phoenix's own `phx.gen.auth` guide states the generated code does **not** inherently protect against user enumeration. So AC2 is real work (Task 2): (a) login sends only for a seeded user with an identical response either way, and (b) the magic-link confirm path must refuse to mint a `User` for an unknown email. Deleting the registration LiveView removes the *form*, not the auto-register *code path* — both must be handled.
- **AD-2 scopes are mandatory from this story on.** `CarWalWeb` never touches `Repo`/schemas/changesets. All data access goes through scope-taking context functions (`def list_things(%Scope{} = scope, ...)`). The generated `:scopes` config + `fetch_current_scope_for_user` plug + `current_scope` assign are the plumbing — keep them intact.
- **AD-13 one live_session, one shell.** Exactly one authenticated `live_session` (the generator's `:require_authenticated_user`). All authenticated LiveViews live in it and share `Layouts.app`. Do not add a second `live_session` or a second layout. Canonical PubSub topics (`"entries"`, `"chat"`, `"location"`) are not this story's concern — don't define any.
- **NFR1 sovereignty is hard.** Outbound mail goes through the German sovereign mailbox (mailbox.org/Posteo) only — `Swoosh.Adapters.SMTP` to a EU provider, never Mailgun/SES/SendGrid (US). The `gen_smtp` dep is the one dep this story adds.
- **German from day one (NFR3).** Magic-link email subject + body, login page strings, settings page strings, flash messages — all German through gettext. The generated strings are English; translate them (the 1.1 pattern: canonical English msgids in code + German in `priv/gettext/de/LC_MESSAGES/default.po`, OR German directly in the notifier's mail body if it bypasses gettext — match the generated notifier's style).
- **Errors convention:** context functions return `{:ok, _} | {:error, _}`; no raising across context boundaries. The generated `Accounts` follows this; keep it.
- **AGENTS.md LiveView rules:** templates start with `<Layouts.app flash={@flash} current_scope={@current_scope} ...>`; use `<.input>` from `core_components.ex` for form fields; `<.flash_group>` is forbidden outside `layouts.ex`; no inline `<script>`; use `~p` verified routes; `<.link navigate={...}>`/`push_navigate` not `live_redirect`; LiveView streams (`stream/3`, `phx-update="stream"`) for any collection (none needed in 1.2, but keep in mind for Epic 2+).

### Verified stack facts (researched 2026-07-06; Phoenix 1.8.8 docs + Swoosh 1.26 docs)

| Item | Fact |
| --- | --- |
| `phx.gen.auth` (1.8.8) | Magic-link **by default** (passwordless). Generates `Accounts` context (`User`, `UserToken`, `Scope`, `UserNotifier`), `CarWalWeb.UserAuth` (plugs + on_mount hooks), `UserSessionController`, `UserLive.{Login,Registration,Settings,Confirmation}`, `users` + `users_tokens` migration, `AccountsFixtures` test helper, `:scopes` config in `config/config.exs`, `fetch_current_scope_for_user` plug in `:browser` pipeline. [Source: https://hexdocs.pm/phoenix/Mix.Tasks.Phx.Gen.Auth.html, https://hexdocs.pm/phoenix/1.8.0/scopes.html] |
| Scope | `%CarWal.Accounts.Scope{user: nil}` struct + `for_user/1`; `:scopes` config wires `assign_key: :current_scope`, `access_path: [:user, :id]`, `schema_key: :user_id`, `test_data_fixture: CarWal.AccountsFixtures`, `test_setup_helper: :register_and_log_in_user`. Context fns take `%Scope{}` first. [Source: https://hexdocs.pm/phoenix/1.8.0/scopes.html] |
| `live_session` | Generator emits `live_session :require_authenticated_user, on_mount: [{CarWalWeb.UserAuth, :ensure_authenticated}]` inside `scope "/" ... pipe_through [:browser, :require_authenticated_user]`. That is the one shell (AD-13). [Source: https://hexdocs.pm/phoenix/1.8.0/scopes.html] |
| `require_sudo_mode` | Generated plug enforcing recent auth for sensitive ops — not needed in 1.2 (no sensitive ops yet); leave the generated code, don't wire extra routes. |
| Session length | **Two independent limits.** (1) Cookie `max_age` (remember-me) and (2) `@session_validity_in_days 60` in `Accounts.UserToken` — `fetch_current_scope_for_user` rejects a DB session token older than this *regardless of cookie max_age*. Cookie-only leaves a hard 60-day ceiling. Set **both** to ~10 years for effectively-never (Task 4). [Source: verified against 1.8 `phx.gen.auth` `UserToken` `@session_validity_in_days`] |
| Enumeration / sign-up | Generated code does **not** protect against user enumeration (Phoenix guide, explicit) and the magic-link flow is also a registration path. AC2 requires active edits (Task 2): gate delivery on a seeded user + identical response, and strip auto-register from the confirm callback. [Source: https://hexdocs.pm/phoenix/mix_phx_gen_auth.html#security-considerations] |
| Swoosh SMTP | `Swoosh.Adapters.SMTP` requires `{:gen_smtp, "~> 1.1"}` (not bundled). STARTTLS on 587: `ssl: false, tls: :always`. Implicit SSL on 465: `ssl: true, tls: :never`. `:from` must be owned by the authenticated account or the server rejects (553). [Source: https://swoosh.hexdocs.pm/Swoosh.Adapters.SMTP.html] |
| Sovereign mailbox SMTP | mailbox.org: `smtp.mailbox.org` 587/465. Posteo: `posteo.de` 587/465. Both standard SMTP, no dedicated adapter. [Source: provider public SMTP settings] |
| Test mailer | `config/test.exs` already `Swoosh.Adapters.Test` — assert against `Swoosh.Adapters.Test` mailbox (`Swoosh.Adapters.Test` stores emails; `assert_email_sent`/`Swoosh.TestAssertions` or inspect the mailbox). Don't change test.exs. |
| Dev mailer | `Swoosh.Adapters.Local` + `/dev/mailbox` preview (already wired in 1.1 dev routes) — magic links land in the local mailbox preview during dev. Don't change dev.exs. |
| PG port | `carwal-pg` on **5433** (not 5432 — collision with `eaf-postgres`). `config/dev.exs` + `config/test.exs` already set `port: 5433`. Migrations run against 5433. |

### Project Structure Notes

- `lib/carwal/accounts.ex` → overwritten by generator (gains `User`, `UserToken`, `Scope`, `UserNotifier` submodules + public functions). AD-1 ownership stays `Accounts`.
- `lib/carwal_web/user_auth.ex` (new) → plugs (`log_in_user`, `log_out_user`, `fetch_current_scope_for_user`, `require_authenticated_user`) + on_mount hooks (`mount_current_scope`, `ensure_authenticated`).
- `lib/carwal_web/live/user_live/{login,settings,confirmation}.ex` + `.html.heex` (new) → `registration.*` deleted (Task 2).
- `lib/carwal_web/user_session_controller.ex` (new) → magic-link callback (`/users/magic/:token`) + logout.
- `lib/carwal_web/components/layouts.ex` → `Layouts.app` nav replaced (Task 6).
- `priv/repo/migrations/*_create_users_tables.exs` (new) → `users` + `users_tokens`, **exactly as `phx.gen.auth` emits** (no hand-added `role` column — reversed; see Task 5).
- `priv/repo/seeds.exs` → three login-capable members, name + email only (Task 5).
- `config/config.exs` → gains `:scopes` config block (generator).
- `config/runtime.exs` → gains prod SMTP mailer block (Task 3).
- `mix.exs` → gains `{:gen_smtp, "~> 1.1"}` (Task 3).
- `test/support/accounts_fixtures.ex` (new, generator) + `:register_and_log_in_user` test helper wired into `:scopes` config.
- No conflict with 1.1 conventions: `tz` 0.28 stays, gettext `de` default stays, PG 5433 stays.

### References

- Epic + ACs: [Source: _bmad-output/planning-artifacts/epics.md#Story 1.2]
- FR10 + NFR1 + onboarding model: [Source: _bmad-output/planning-artifacts/prds/prd-carwal-2026-07-05/prd.md#FR10, #NFR1] [Source: .../addendum.md#Auth model, #Messages]
- Binding invariants AD-1, AD-2, AD-13, conventions (Outbound mail, Errors, Tests): [Source: _bmad-output/planning-artifacts/architecture/architecture-carwal-2026-07-05/ARCHITECTURE-SPINE.md]
- Deferred items this story closes: [Source: _bmad-output/implementation-artifacts/deferred-work.md — "Prod mailer has no real adapter → Story 1.2", "Nav shell is unmodified starter promo → Story 1.2+", "data_case.ex errors_on/1 docstring → Story 1.2"]
- Previous story learnings (1.1): [Source: _bmad-output/implementation-artifacts/1-1-app-skeleton-from-phoenix-starter.md#Dev Notes, #Completion Notes List]
- Phoenix conventions (LiveView, forms, layouts, scopes): [Source: AGENTS.md]
- Stack facts verified against hexdocs (Phoenix 1.8.8 phx.gen.auth + scopes guide, Swoosh 1.26 SMTP adapter), 2026-07-06

## Dev Agent Record

### Agent Model Used

claude-opus-4-8[1m] (Opus 4.8, 1M context)

### Debug Log References

- `mix phx.gen.auth Accounts User users` (auto-accepted prompts). All generated files landed.
- `mix precommit` → 90 passed, 0 failures; compile --warnings-as-errors clean; formatted.
- `mix ecto.reset` → migrations + seeds replay cleanly; dev DB seeds 3 users (`@carwal.local` placeholders + stderr warning).

### Completion Notes List

**Key deviation — full password strip (operator-approved).** Phoenix **1.8.8** `phx.gen.auth` does NOT generate passwordless-only; it generates a **hybrid** (magic-link + optional password) and adds `{:bcrypt_elixir, "~> 3.0"}` unconditionally — there is no "decline password" prompt. Per FR10 (passwordless) and the operator's explicit choice ("Voll entfernen"), password was **fully removed**: bcrypt dep, `hashed_password` column, `password`/`hashed_password` User fields, `password_changeset`/`valid_password?`, `get_user_by_email_and_password`/`change_user_password`/`update_user_password`, the password login form + `#password_form` settings section + `/users/update-password` route, and all password tests. The generator's own docs flag the magic-link+password combo as an account-hijack vector — removing password closes it. Story Task 1's "decline bcrypt" was thus implemented as *remove*, not *decline*.

**AC1 — session widened to effectively-never (~10 years) per operator.** Two layers both raised from the generated **14** days (not the 60 the grilling assumed) to **3650**: `@session_validity_in_days` in `UserToken` (the DB-side binding limit) AND `@max_cookie_age_in_days` in `UserAuth`. Confirmation LiveView's "log in only this time" buttons removed so every login is long-lived (`remember_me: true`). Test `auth_guarantees_test.exs` travels a session token's `inserted_at` back ~400 days and asserts it is still valid — the cookie assertion alone (in `user_auth_test.exs`, bumped to 3650) would pass while the real session was already dead at 14 days.

**AC2 — no enumeration / no sign-up enforced in code.** Login gates `deliver_login_instructions` on `get_user_by_email/1` and returns an identical German flash regardless (`login.ex`). Registration route + LiveView deleted; `login_user_by_magic_link` cannot mint a user for an unknown token (no token row exists for an unseeded email → `{:error, :not_found}`). Tests assert: unseeded email → 0 users, 0 tokens; unknown magic token → 0 users.

**Generator injected into the 1.1 stub instead of overwriting** — so `import Ecto.Query` + `alias CarWal.Repo` were missing from `accounts.ex` (would not compile). Added them; updated the stale moduledoc.

**No `name` column seeded.** `users` has no name (generator emits none, nothing in 1.2 reads one) — same YAGNI call as the dropped `role`. Seed persists email only; config `:name` is an operator-facing label until a name is shown in the UI (Epic 2).

**German (NFR3):** all login/settings/confirmation/notifier/controller user-facing strings translated inline (single-locale app; no gettext ceremony added).

**Deferred (out of Story 1.2 scope):**
- "5 members" wording is stale (household is 4 / 3 login-capable) — fix in `CLAUDE.md`, PRD, epics separately.
- Home page `/` (`page_html/home.html.heex`) is the Phoenix starter promo and does NOT use `<Layouts.app>`, so the new nav shell + login link don't render there. Left as-is — Epic 2 replaces `/` with the authenticated agenda LiveView (which uses the shell). AC3's nav-shell requirement is verified on authenticated pages.
- 9yo daughter → future tracked-person entity (Epic 2), not a `User`.
- Manual browser smoke **run** (Chrome, 2026-07-06) — full happy path verified end-to-end: login page (German, no password field, no register link) → seeded email submit → enumeration-safe German flash → German magic-link mail in `/dev/mailbox` (`From: "CarWal" <carwal@carwal.local>`, subject "CarWal: Konto bestätigen") → confirm-and-stay-logged-in → session established → `/users/settings` shows the nav shell (email, Einstellungen, Abmelden) with **only** an email form (no password) → logout → unseeded email submit yields the **identical** flash and **no** new mail. Recording exported as `story-1-2-magic-link-smoke.gif`. Confirmed the reviewer's note: home `/` uses its own header (not `Layouts.app`), so the auth nav does not render there.

### File List

**Generated (new, kept):** `lib/carwal/accounts/{scope,user,user_token,user_notifier}.ex`, `lib/carwal_web/user_auth.ex`, `lib/carwal_web/controllers/user_session_controller.ex`, `lib/carwal_web/live/user_live/{login,settings,confirmation}.ex`, `priv/repo/migrations/20260706210654_create_users_auth_tables.exs`, `test/support/fixtures/accounts_fixtures.ex`, `test/carwal/accounts_test.exs`, `test/carwal_web/user_auth_test.exs`, `test/carwal_web/controllers/user_session_controller_test.exs`, `test/carwal_web/live/user_live/{login,settings,confirmation}_test.exs`.

**Modified:** `mix.exs` (−bcrypt, +gen_smtp), `mix.lock`, `config/config.exs` (:family_members placeholders), `config/runtime.exs` (SMTP + :family_members via env), `config/test.exs` (−bcrypt log_rounds), `lib/carwal/accounts.ex` (password strip + imports), `lib/carwal/accounts/{user,user_token,user_notifier}.ex`, `lib/carwal_web/user_auth.ex` (cookie 3650), `lib/carwal_web/controllers/user_session_controller.ex`, `lib/carwal_web/live/user_live/{login,settings,confirmation}.ex`, `lib/carwal_web/router.ex` (−register, −update-password), `lib/carwal_web/components/layouts.ex` (nav shell) + `layouts/root.html.heex` (−dup menu), `priv/repo/seeds.exs`, `test/support/{conn_case,data_case}.ex`, `AGENTS.md` (generator injection).

**New (this story):** `test/carwal_web/auth_guarantees_test.exs`, `test/carwal/seeds_test.exs`.

**Deleted:** `lib/carwal_web/live/user_live/registration.ex` + `registration_test.exs`.

## Change Log

- 2026-07-06: Story 1.2 created from epics + architecture spine + PRD + 1.1 learnings + Phoenix 1.8.8 / Swoosh 1.26 web research. Status → ready-for-dev.
- 2026-07-06: Grilling pass (7 revisions, verified against Phoenix 1.8 `phx.gen.auth` docs):
  1. No-enumeration + no-sign-up promoted from "verify" to active code (Task 2): the generator does **not** protect against enumeration, and its magic-link flow auto-registers — both handled in code + tests.
  2. Session longevity fixed: cookie `max_age` alone is capped at 60 days by `@session_validity_in_days` — **both** layers raised to ~10 years (effectively-never per operator); test asserts token-age survival (Task 4, 7).
  3. `role` column **dropped** — enum was factually wrong (no "father"; operator is a person+partner) and unread in 1.2. Migration = pure generator output. Roles → Epic 2 (Task 5).
  4. Seed = **3 login-capable members** (operator, mother, 15yo daughter). 9yo daughter excluded from `users` (no mailbox; future tracked-person concept) (AC1, Task 5).
  5. PII out of git: emails via env in `runtime.exs`, committed config = placeholders, **prod seed refuses placeholders** (Task 5).
  6. Removed-behavior tests pruned (registration + auto-register), fixtures kept, security + session-age tests added; `create_user/1` refs to reconcile to actual generated fn name (Task 2, 5, 7).
  7. **Follow-up (out of this story):** "5 members" is stale — household is 4 people / 3 login-capable. Fix wording in `CLAUDE.md`, PRD, and epics separately.
- 2026-07-06: Story 1.2 implemented via `phx.gen.auth` + full password strip (operator-approved) + Tasks 2–7. `mix precommit` green (90 passed). Status → review. See Completion Notes for the password-strip deviation, the 14→3650-day session fix, and deferred items.
- 2026-07-06: Two-axis code review (Standards + Spec, parallel sub-agents). No blocking findings. Fixes applied:
  - Standards: removed dead `config/test.exs` bcrypt comment (comment rot); translated 3 remaining English flashes in `user_auth.ex` (require_authenticated/require_sudo) to German (NFR3) + updated their test assertions.
  - Spec: added `seeds_test.exs` case proving the prod placeholder guard raises with a real mail adapter (was untested).
  - Noted, not changed: enumeration test asserts `UserToken` presence rather than the Swoosh mailbox (reviewer: equivalent/stronger; avoids LiveView process-boundary flakiness); `login_user_by_magic_link` hard-matches `verify_magic_link_token_query` so a malformed-base64 token → MatchError/500 instead of a clean reject (stock generator code; creates no user/session; user-facing path uses the safe `with` variant) — deferred.
  - `mix precommit` green (91 passed) after fixes.
- 2026-07-07: Closed the "5 members" follow-up (grilling item 7): corrected the stale household headcount in `CLAUDE.md`, the bmad PRD, `epics.md`, `docs/PRD-family-app.md`, and the readiness report to "4-person household, 3 login-capable". Left "5 users, few writes/day" scale-rhetoric in architecture-rationale/review docs (order-of-magnitude, immaterial at 4 vs 5).