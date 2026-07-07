---
baseline_commit: bd014d722ac8ca3ab1f02e967858e945e6b0da70
---

# Story 1.4: PWA Install + Push Foundation

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->
<!-- baseline_commit: to be stamped by dev-story at implementation start. Branch off main (3e1d50b,
     which has Story 1.3 done + the CodeRabbit follow-up merged). -->

## Story

As a family member,
I want to install CarWal to my home screen and receive a test push,
so that the app feels native and notifications provably arrive on my device.

## Acceptance Criteria

1. **Given** the HTTPS-served app on Android Chrome, **when** the member uses "Add to home screen", **then** the PWA installs with manifest icon + name and opens standalone (`display: standalone`).
2. **Given** an installed/authenticated PWA, **when** the member grants notification permission and taps "activate", **then** exactly one service worker registers and the subscription is stored per device via `Notifications.register_subscription(user, endpoint, keys)` keyed `(user_id, endpoint)` (AD-13) **and** a "send me a test push" action delivers a minimal-payload push (ex_nudge / VAPID) to that device.
3. **Given** a second device of the same user, **when** it subscribes, **then** both subscriptions coexist in `push_subscriptions` (different `endpoint`, same `user_id`) and both receive the test push.

## Tasks / Subtasks

-- [x] Task 1: Add `ex_nudge` + VAPID config (AC: 2)
  - [x] Add `{:ex_nudge, "~> 1.0"}` to `mix.exs` `deps/0` and `mix deps.get`. Current ex_nudge is **1.0.2**. It pulls **HTTPoison** transitively (CarWal uses Req elsewhere — no conflict, but a second HTTP client enters the release; do not "fix" this by swapping ex_nudge for a Req-based push lib, the spine pins ex_nudge 1.0.x).
  - [x] Generate a **dev/test** VAPID keypair: `mix run -e 'IO.inspect(ExNudge.generate_vapid_keys())'`. Commit it in `config/config.exs`:
    ```elixir
    config :ex_nudge,
      vapid_subject: "mailto:operator@carwal.local",
      vapid_public_key: "<dev public key>",
      vapid_private_key: "<dev private key>"
    ```
    These dev keys are **not secret** — they mirror the committed `signing_salt` / dev `secret_key_base` in `config/dev.exs` + `config/test.exs`. Dev/test only; prod must override.
  - [x] Prod: in `config/runtime.exs` inside the `if config_env() == :prod do` block, read `VAPID_PUBLIC_KEY` + `VAPID_PRIVATE_KEY` via the existing `read_env` helper and **raise if missing/empty** (mirror `SECRET_KEY_BASE` / `SMTP_PASSWORD` — controlled boot failure, not a silent no-push). `VAPID_SUBJECT` defaults to `"mailto:" <> mail_from` where `mail_from` is the already-bound `MAIL_FROM` (or `SMTP_USERNAME`); accept an explicit `VAPID_SUBJECT` env override. Then:
    ```elixir
    config :ex_nudge,
      vapid_subject: vapid_subject,
      vapid_public_key: vapid_public_key,
      vapid_private_key: vapid_private_key
    ```
  - [x] Extend `deploy/README.md` env contract with: `VAPID_PUBLIC_KEY` + `VAPID_PRIVATE_KEY` (required, raise at boot if missing/empty — generate with `mix run -e 'IO.inspect(ExNudge.generate_vapid_keys())'` locally and paste into `.env.prod`), optional `VAPID_SUBJECT` (default `mailto:<MAIL_FROM>`). Prod VAPID keys are **never** committed (same rule as `SECRET_KEY_BASE` / `SMTP_PASSWORD`). Note a redeploy is required for the first push-capable build (new dep + new migration; `deploy.sh` rebuilds the image and runs `Release.migrate()` automatically).
- [x] Task 2: `push_subscriptions` schema + migration (AC: 2, 3; AD-1, AD-13)
  - [x] `lib/carwal/notifications/push_subscription.ex` — Ecto schema for the `push_subscriptions` table (Notifications owns it per AD-1). Fields: `id`, `user_id` (`belongs_to :user`, `CarWal.Accounts.User`), `endpoint` (`:string`, `null: false`), `p256dh` (`:string`, `null: false`), `auth` (`:string`, `null: false`), timestamps `type: :utc_datetime`. No `expiration_time` column in v1 — the browser usually sends `null` and nothing reads it (YAGNI; add when a feature needs it).
  - [x] Migration `priv/repo/migrations/<timestamp>_create_push_subscriptions.exs`: `create table(:push_subscriptions)` with `add :user_id, references(:users, on_delete: :delete_all)`, `add :endpoint, :string, null: false`, `add :p256dh, :string, null: false`, `add :auth, :string, null: false`, timestamps; then `create unique_index(:push_subscriptions, [:user_id, :endpoint])`. **This unique index IS the AD-13 `(user_id, endpoint)` key** — a second device of the same user has a different `endpoint`, so it inserts (AC3); re-subscribing the same device upserts (Task 3).
  - [x] Changeset: `cast(..., [:user_id, :endpoint, :p256dh, :auth])` + `validate_required([...])` + `unique_constraint([:user_id, :endpoint])`.
- [x] Task 3: `Notifications` context API — the single push pipeline (AC: 2, 3; AD-7, AD-13)
  - [x] Replace the `lib/carwal/notifications.ex` stub with the real context. `alias CarWal.Notifications.PushSubscription`, `alias CarWal.Repo`, `import Ecto.Query`. All public functions return `{:ok, _} | {:error, _}` (spine Errors convention):
    - `register_subscription(user, endpoint, keys)` where `keys` is `%{p256dh: String.t(), auth: String.t()}` — **upsert** keyed `(user_id, endpoint)`: on conflict, update `p256dh`/`auth` (browser key rotation). Use `Repo.insert(changeset, conflict_target: {:unsafe, [:user_id, :endpoint]}, on_conflict: :replace_all, conflict_target_constraint: ...) ` or `{:conflict, replace: [:p256dh, :auth, :updated_at]}` — pick the smallest working form; the goal is idempotent re-subscribe. Return `{:ok, sub}`.
    - `list_subscriptions_for_user(user)` → `PushSubscription` list for the device list + test push.
    - `unsubscribe(user, endpoint)` → delete the `(user_id, endpoint)` row (scoped to `user.id` so a member can only drop their own subs). Return `{:ok, _}`.
    - `send_test_push(user)` → for each `list_subscriptions_for_user/1`, build `%ExNudge.Subscription{endpoint: sub.endpoint, keys: %{p256dh: sub.p256dh, auth: sub.auth}}` and call the private `send/2` with a minimal German payload (e.g. `"Test-Benachrichtigung von CarWal"`). Return `{:ok, sent_count}` (or `{:ok, results}`).
    - Private `send(subscription, payload)` — wraps `ExNudge.send_notification/2`; on `{:error, :subscription_expired}` **delete the stale sub** (cleanup — keeps the table from rotting) and continue; `Logger.warning` other errors and continue. **AD-7: only `Notifications` calls `ExNudge`** — future stories (2.5, 3.3, 3.4) call `Notifications.send_*`, never ex_nudge directly. This is the foundation of the single push pipeline.
- [x] Task 4: PWA manifest + service worker + static plumbing (AC: 1)
  - [x] `priv/static/manifest.json`: `name: "CarWal"`, `short_name: "CarWal"`, `start_url: "/"`, `scope: "/"`, `display: "standalone"`, `background_color` + `theme_color` (pick a value matching the daisyUI base palette; document the choice), `icons: [{"src": "/images/logo.svg", "sizes": "any", "type": "image/svg+xml", "purpose": "any maskable"}]` — reuse the existing `priv/static/images/logo.svg`.
    - **Guardrail (verified 2026-07):** current Chrome accepts a single SVG icon with `sizes: "any"` for installability — ship SVG-only first (ponytail: shortest path). **Only if** the live Android Chrome smoke test (Task 9) reports the app not installable without raster icons, generate `priv/static/images/icon-192.png` + `icon-512.png` from `logo.svg` (e.g. `rsvg-convert -w 512 -h 512 priv/static/images/logo.svg > priv/static/images/icon-512.png`) and add both entries to `icons`. Do not pre-generate PNGs speculatively.
  - [x] `priv/static/sw.js` — minimal service worker: `push` event → `event.waitUntil(self.registration.showNotification("CarWal", {body: event.data?.text() ?? "", icon: "/images/logo.svg", badge: "/images/logo.svg", data: {url: "/"}}))`; `notificationclick` → `event.waitUntil(clients.matchAll({type:'window'}).then(...openWindow("/")))`. **No precaching / no fetch handler** — the app is online-first over LiveView; a precache layer is YAGNI and would just stale the LiveView WS.
  - [x] `lib/carwal_web.ex` `static_paths/0`: add `"manifest.json"` and `"sw.js"` to the `only` list so `Plug.Static` serves them at root. Reference them with **literal paths** (`href="/manifest.json"`, `register('/sw.js')`), **not `~p`** — the URL must stay stable (the SW scope depends on it). `mix phx.digest` will also create digested siblings + a `.gz`, but the originals at `/manifest.json` + `/sw.js` remain served by `Plug.Static`, so the literal paths keep working.
  - [x] `lib/carwal_web/components/layouts/root.html.heex` `<head>`: add `<link rel="manifest" href="/manifest.json" />`, `<meta name="theme-color" content="<same as manifest theme_color>" />`, `<meta name="apple-mobile-web-app-capable" content="yes" />`, `<meta name="apple-mobile-web-app-status-bar-style" content="default" />`, `<link rel="apple-touch-icon" href="/images/logo.svg" />`. Keep the existing theme script untouched.
  - [x] `start_url: "/"` lands a logged-in member on the Phoenix starter promo (root `/` is promo until Epic 2's agenda view — Story 1.3 noted this). Accepted for 1.4; do not build a landing page here.
- [x] Task 5: Push subscription controller — JSON endpoints (AC: 2, 3)
  - [x] `lib/carwal_web/controllers/push_controller.ex` (`use CarWalWeb, :controller`). Actions read `conn.assigns.current_scope.user`; if absent, return **401 JSON** (`put_status(:unauthorized) |> json(%{error: "unauthenticated"})`) — do **not** use `require_authenticated_user`, that plug redirects to the login page (HTML), wrong for a JSON API.
    - [x] `subscribe/2` — parse `%{"endpoint" => e, "keys" => %{"p256dh" => p, "auth" => a}}`; `Notifications.register_subscription(user, e, %{p256dh: p, auth: a})` → `201` + `%{ok: true}` on `{:ok, _}`, `422` + errors on `{:error, changeset}`.
    - [x] `unsubscribe/2` — parse `%{"endpoint" => e}`; `Notifications.unsubscribe(user, e)` → `200` (or `404` if nothing deleted).
  - [x] Routes in `lib/carwal_web/router.ex` — a dedicated `:push` pipeline (cookie-auth + CSRF, JSON accepts) and scope. The browser `fetch` from the SW page sends the session cookie same-origin; CSRF is enforced via the header token the JS hook already has:
    ```elixir
    pipeline :push do
      plug :accepts, ["json"]
      plug :fetch_session
      plug :protect_from_forgery
      plug :fetch_current_scope_for_user
    end

    scope "/push", CarWalWeb do
      pipe_through [:push]
      post "/subscribe", PushController, :subscribe
      post "/unsubscribe", PushController, :unsubscribe
    end
    ```
    (`fetch_current_scope_for_user` + `protect_from_forgery` are imported via `import CarWalWeb.UserAuth` already at the top of the router.) The controller's 401 check is the auth gate; `protect_from_forgery` is the CSRF gate (rejects POSTs lacking a valid `x-csrf-token`).
- [x] Task 6: Push settings LiveView (AC: 2, 3)
  - [x] `lib/carwal_web/live/user_live/push_settings.ex` (`use CarWalWeb, :live_view`). Route `live "/users/push", UserLive.PushSettings, :edit` **inside the existing `live_session :require_authenticated_user`** (AD-13: one live_session/shell — do not create a second live_session).
  - [x] `mount/3`: `user = current_scope.user`; `assign(socket, subscriptions: Notifications.list_subscriptions_for_user(user))`; `assign(socket, vapid_public_key: Application.get_env(:ex_nudge, :vapid_public_key))`.
  - [x] `render/1`: a push-setup container `id="push-setup" phx-hook="Push" data-vapid-key={@vapid_public_key}` with an "Benachrichtigungen aktivieren" button (plain HTML — the JS hook owns the click, not `phx-click`); the device list (`@subscriptions`) showing a truncated `endpoint` + per-device "Test-Push senden" (`phx-click="send_test_push" phx-value-endpoint={sub.endpoint}`) + "Abbestellen" (`phx-click="unsubscribe" phx-value-endpoint={sub.endpoint}`); and a global "An alle Geräte senden" (`phx-click="send_test_push_all"`). All user-visible strings via `gettext`, German.
  - [x] `handle_event`: `"send_test_push"` → `Notifications.send_test_push_to(user, endpoint)` (or filter `send_test_push` to one endpoint); `"send_test_push_all"` → `Notifications.send_test_push(user)`; `"unsubscribe"` → `Notifications.unsubscribe(user, endpoint)`; `"push_subscribed"` / `"push_unsubscribed"` (pushed from the JS hook) → re-query `Notifications.list_subscriptions_for_user/1` and `assign(:subscriptions, ...)`. Flash German success/error (`put_flash`).
  - [x] Link from `lib/carwal_web/live/user_live/settings.ex` ("Einstellungen") to `~p"/users/push"` ("Benachrichtigungen") so the page is reachable.
  - [x] `send_test_push_to/2` (single endpoint) — add to `Notifications` alongside `send_test_push/1` (AC2's per-device test push) and reuse the private `send/2`.
- [x] Task 7: JS push hook + SW registration (AC: 1, 2)
  - [x] `assets/js/push.js` — a Phoenix LiveView hook object (`{mounted() {...}}`) exported and added to the `hooks` map in `assets/js/app.js` (`hooks: {...colocatedHooks, Push}`). On `mounted`: read `this.el.dataset.vapidKey`; `navigator.serviceWorker.register('/sw.js')` (idempotent — registering an already-registered SW is a no-op, satisfying AC2's "exactly one service worker"); attach a click listener to the enable button.
  - [x] Enable-button click handler:
    ```js
    const reg = await navigator.serviceWorker.ready
    const perm = await Notification.requestPermission()
    if (perm !== 'granted') { /* flash "abgelehnt" via pushEvent */ return }
    const sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(this.el.dataset.vapidKey)
    })
    await fetch('/push/subscribe', {
      method: 'POST',
      headers: {'Content-Type': 'application/json', 'x-csrf-token': csrfToken},
      body: JSON.stringify(sub),
      credentials: 'same-origin'
    })
    this.pushEvent('push_subscribed')
    ```
    (`csrfToken` is already read at the top of `app.js` — reuse it; do not re-query.)
  - [x] **CRITICAL guardrail — do NOT copy the ex_nudge readme placeholder.** It shows `applicationServerKey: 'your_vapid_public_key'` as a string. The browser `PushManager.subscribe` **requires a `BufferSource` (Uint8Array)**, not a string — a string silently fails or throws. Ship a `urlBase64ToUint8Array(base64String)` helper: pad to a multiple of 4, `atob`, map to char codes, `new Uint8Array(arr)`. This is the single most likely LLM-dev mistake in this story.
  - [x] Browser-side unsubscribe hygiene is optional for v1 — the server deletes the row on "Abbestellen" (Task 6); the browser's `PushSubscription` persists until the member revokes notification permission. Note this; do not build a client-side `subscription.unsubscribe()` round-trip unless the live test shows stale pushes.
  - [x] The `push` + `notificationclick` handlers live in `sw.js` (Task 4), **not** in the hook.
- [x] Task 8: Tests (AC: 1, 2, 3)
  - [x] `test/carwal/notifications_test.exs` (DataCase): `register_subscription` inserts; re-subscribing the same `(user, endpoint)` upserts (keys rotate, no duplicate row); a second `endpoint` for the same user **coexists** (AC3 — assert `list_subscriptions_for_user/1` returns 2); `list_subscriptions_for_user/1` returns only that user's subs (not another user's); `unsubscribe/2` deletes the row and is scoped (cannot delete another user's sub). Use the accounts fixture (`CarWal.AccountsFixtures` / `register_and_log_in_user` setup).
  - [x] Push-send unit test: ex_nudge has **no behaviour** to Mox. Do not stand up a full Mox layer for one call. Instead: extract the per-sub send into the private `send/2` and unit-test the **`:subscription_expired` cleanup path** by injecting a fake send function (or assert via a thin internal seam) — verify an expired sub is deleted and a healthy sub is kept. The real `ExNudge.send_notification/2` round-trip is proven by the **live smoke test (Task 9)**, not a unit test against FCM. (ponytail: the smallest check that fails if the cleanup logic breaks; do not mock the internet.)
  - [x] `test/carwal_web/controllers/push_controller_test.exs` (ConnCase + logged-in user): `subscribe` → `201` + row created in `push_subscriptions`; missing/empty `keys` → `422`; no session → `401`; POST without `x-csrf-token` → forbidden (CSRF enforced). `unsubscribe` → `200` + row deleted; no session → `401`.
  - [x] `test/carwal_web/live/user_live/push_settings_test.exs`: one render smoke test (mounts logged-in, shows the enable button + device list); `"unsubscribe"` event removes the sub from the list; `"send_test_push_all"` event sets a flash (stub the `Notifications.send_test_push/1` send seam so no real HTTP). One render smoke test per LiveView is the spine convention.
  - [x] `mix precommit` green (compile --warnings-as-errors, deps.unlock --unused, format, test) against local `carwal-pg` on **5433**. `deps.unlock --unused` must not flag ex_nudge (it's used in `Notifications`); the transitive HTTPoison is expected.ck --unused` must not flag ex_nudge (it's used in `Notifications`); the transitive HTTPoison is expected.
- [x] Task 9: Live smoke test on Android Chrome — operator step (AC: 1, 2, 3)
  - [x] **Preconditions (operator, not the loop — HALT and ask if missing):** deployed app reachable at `https://carwal.cloud` (Story 1.3 done); an Android device with Chrome; `VAPID_PUBLIC_KEY` + `VAPID_PRIVATE_KEY` in `~/carwal/.env.prod` on the VPS; a redeploy run so the new image (ex_nudge) + new migration ship.
  - [x] Redeploy: `CARWAL_HOST=root@<vps> CARWAL_DOMAIN=carwal.cloud ./deploy/deploy.sh` (rebuilds image with ex_nudge, runs `Release.migrate()` → `push_subscriptions` table). Verify `https://carwal.cloud/health` → 200.
  - [x] AC1: on Android Chrome, open `https://carwal.cloud/users/push` (logged in), "Add to home screen" → installs with the CarWal name + logo, opens standalone (no Chrome chrome). If Chrome refuses to install with SVG-only icons, apply the PNG fallback from Task 4 and redeploy.
  - [x] AC2: "Benachrichtigungen aktivieren" → grant permission → exactly one SW registers (DevTools → Application → Service Workers shows one) → subscription stored. Verify in DB: `ssh root@<vps> "cd ~/carwal && docker compose exec -T db psql -U carwal -d carwal -c 'select id, user_id, left(endpoint,40) as endpoint from push_subscriptions;'"` shows one row for the user. "Test-Push senden" → the push arrives on the device (tap opens the app).
  - [x] AC3: subscribe a second device (e.g. the operator's other browser/profile) → DB shows two rows, same `user_id`, different `endpoint`. "An alle Geräte senden" → both devices receive the push.
  - [x] Operator confirmed 2026-07-07: VAPID keys deployed to VPS `.env.prod`, redeploy ran, Android Chrome install + push smoke test passed.

### Review Findings

**Patch** (fixable now, unambiguous):
- [x] [Review][Patch] SSRF: unvalidated push endpoint URL allows server-side requests to attacker-controlled hosts [lib/carwal/notifications.ex:91, lib/carwal_web/controllers/push_controller.ex:6] — fixed: `PushSubscription.changeset/2` now validates `https` scheme + known push-service host suffix allowlist
- [x] [Review][Patch] `send_fun` test seam leaked as public parameter on `send_test_push/2` and `send_test_push_to/3`, undermining AD-7 single-pipeline guarantee [lib/carwal/notifications.ex:64] — fixed: public 1-/2-arg functions always use the configured client; the 2-/3-arg test seam is `@doc false`
- [x] [Review][Patch] `push_controller.ex#subscribe` reimplements changeset error translation via regex instead of reusing `CarWalWeb.CoreComponents.translate_error/1` [lib/carwal_web/controllers/push_controller.ex:19] — fixed
- [x] [Review][Patch] `push_controller.ex#unsubscribe/2` has no catch-all clause for a missing `endpoint` key — `FunctionClauseError` (500) on malformed request [lib/carwal_web/controllers/push_controller.ex:42] — fixed: added catch-all clause
- [x] [Review][Patch] Concurrent unsubscribe race: `Notifications.unsubscribe/2` and the `:subscription_expired` cleanup both raise `Ecto.StaleEntryError` when the row was already deleted (double-click, multi-tab/device) [lib/carwal/notifications.ex:52, lib/carwal/notifications.ex:106] — fixed: both now use a single atomic `Repo.delete_all` by filter, no fetch-then-delete race
- [x] [Review][Patch] `push.js` gives no user-facing feedback on subscribe failure (server rejection or thrown exception) — silently console-logged only [assets/js/push.js:63] — fixed: emits `push_subscribe_failed` event, flashed by the LiveView
- [x] [Review][Patch] Permission-denied path reuses the `push_unsubscribed` event, producing a misleading "Gerät abbestellt" flash for a user who never subscribed [assets/js/push.js:42, lib/carwal_web/live/user_live/push_settings.ex:178] — fixed: dedicated `push_permission_denied` event + message
- [x] [Review][Patch] `:web_push` router pipeline omits `put_secure_browser_headers` (present in `:browser`) [lib/carwal_web/router.ex:24] — fixed
- [x] [Review][Patch] `PushSubscription.changeset/2` keeps a `unique_constraint([:user_id, :endpoint])` that is unreachable dead code since `register_subscription/3` always upserts on that same conflict target [lib/carwal/notifications/push_subscription.ex:19] — fixed: removed, replaced by the endpoint-validation change above
- [x] [Review][Patch] Committed VAPID dev keypair has no comment flagging intentional non-secret status for secret scanners [config/config.exs] — fixed: comment added
- [x] [Review][Patch] `push-setup` hook div lacks `phx-update="ignore"` — cheap insurance against a future LiveView patch detaching the click listener [lib/carwal_web/live/user_live/push_settings.ex:18] — fixed: hook scoped to its own `phx-update="ignore"` wrapper (device list stays reactive)

**Deferred** (real, not blocking this story):
- [x] [Review][Defer] `sw.js` notification-click focus logic is moot since the push payload `data.url` is hardcoded to `'/'` — real fix belongs with the notification-content stories (3.3/3.4) [priv/static/sw.js:8] — deferred, out of scope for the foundation story
- [x] [Review][Defer] No `pushsubscriptionchange` listener in `sw.js` to handle silent browser-side key rotation [priv/static/sw.js] — deferred, low-probability edge case
- [x] [Review][Defer] No `endpoint` length validation before insert (Postgres btree index row-size limit); real push endpoints are far under this in practice [lib/carwal/notifications/push_subscription.ex] — deferred, theoretical
- [x] [Review][Defer] `list_subscriptions_for_user/1` is unbounded with no ordering/limit — fine at family-app device-count scale [lib/carwal/notifications.ex:42] — deferred, pre-existing scale assumption
- [x] [Review][Defer] `navigator.serviceWorker.ready` await has no timeout; hangs silently if SW registration stalls [assets/js/push.js:40] — deferred, low-probability edge case
- [x] [Review][Defer] `config/test.exs` uses one global `:web_push_client` stub for the whole suite instead of per-test override — works today since callers can pass `send_fun` directly [config/test.exs] — deferred, no current test needs per-test variation

## Dev Notes

### Critical guardrails (read before coding)

- **AD-13 is the whole point of this story.** Exactly one service worker, one push JS hook, one push pipeline. `push_subscriptions` is keyed `(user_id, endpoint)` so a user's many devices coexist — do NOT key on `user_id` alone (that would force one-device-per-user and break AC3) and do NOT key on `endpoint` alone (two family members could share a device profile). The unique index from Task 2 is the enforcement.
- **AD-7: only `Notifications` sends Web Push.** `Notifications` is the only module that calls `ExNudge`. Web/`Ingestion`/`Chat`/`Location` call `Notifications.send_*`. This story ships the foundation (`register_subscription`, `send_test_push`, private `send/2`); the routing defaults (school → mother, digest → adults, …) land in Epic 2/3. Do not build routing here.
- **AD-2: the web layer never touches Repo.** `PushController` + `PushSettings` LiveView call `Notifications.*` only — never `Repo`, never the `PushSubscription` schema/changeset directly.
- **Do not touch auth/login code.** Story 1.2 is done and reviewed. This story adds routes inside the existing `live_session :require_authenticated_user` and reuses `fetch_current_scope_for_user`; no changes to `UserAuth`, `UserToken`, login/confirmation LiveViews, or the session cookie config.
- **HTTPS is required for Web Push + SW.** Already provided by Caddy (Story 1.3). Local dev over `http://localhost:4000` is fine for SW registration (Chrome treats localhost as secure), but the install + push ACs are verified live over HTTPS (Task 9).
- **VAPID keys are prod secrets.** Dev/test keypair is committed (non-secret, like signing salts); prod keypair comes from `.env.prod` env vars and is **never** committed. Missing prod VAPID keys raise at boot — controlled failure, not silent no-push.
- **The `applicationServerKey` must be a `Uint8Array`, not a string.** The ex_nudge readme shows a string placeholder — copying it verbatim is the #1 failure mode here. Use `urlBase64ToUint8Array` (Task 7).
- **Errors convention:** `Notifications.*` returns `{:ok, _} | {:error, _}`; `PushController` maps those to HTTP status. `Logger.warning` on push-send failure (do not raise across the context boundary); `:subscription_expired` deletes the stale row.
- **German UI (NFR3):** all user-visible strings in the LiveView + push body via `gettext`, German default. The `/health` endpoint stays plain `"ok"` (machine, exempt).
- **One environment.** Prod on the VPS + local dev; no staging. `deploy.sh` is the pipeline; the first push-capable build needs a redeploy (new dep + migration).

### Verified stack facts (researched 2026-07-07; hexdocs / GitHub / official docs)

| Item | Fact |
| --- | --- |
| ex_nudge 1.0.2 | Pure-Elixir Web Push: RFC 8291 (payload encryption) + RFC 8292 (VAPID). Dep: `{:ex_nudge, "~> 1.0"}`. VAPID config: `config :ex_nudge, vapid_subject:, vapid_public_key:, vapid_private_key:`. Keys: `ExNudge.generate_vapid_keys/0` → `%{public_key:, private_key:}` (base64url strings). Send: `ExNudge.send_notification(%ExNudge.Subscription{endpoint:, keys: %{p256dh:, auth:}, metadata:}, payload, opts)` → `{:ok, %HTTPoison.Response{status_code: 201}}` \| `{:error, :subscription_expired}` \| `{:error, reason}`. Opts: `:ttl` (default 60), `:urgency` (`:very_low`\|`:low`\|`:normal`\|`:high`), `:topic`. Uses **HTTPoison** (not Req). [Source: https://hexdocs.pm/ex_nudge/ExNudge.html, https://hex.pm/packages/ex_nudge] |
| Browser push client | `navigator.serviceWorker.register('/sw.js')` (idempotent); `await navigator.serviceWorker.ready`; `reg.pushManager.subscribe({userVisibleOnly: true, applicationServerKey: <Uint8Array>})` — `applicationServerKey` is the VAPID public key as a `BufferSource` (base64url-decode to `Uint8Array`, **not** a string). `PushSubscription.toJSON()` → `{endpoint, keys: {p256dh, auth}, expirationTime}` — that is the JSON to POST. `Notification.requestPermission()` → `"granted"`/`"denied"`/`"default"`. [Source: https://developer.mozilla.org/en-US/docs/Web/API/PushManager/subscribe, ex_nudge readme] |
| Phoenix 1.8.8 PWA | `mix phx.new` generates **no** PWA files — no `manifest.json`, no service worker, no `<link rel="manifest">`. Add manually: `priv/static/manifest.json`, `priv/static/sw.js`, manifest link in `root.html.heex`, SW register in `app.js`. No `--pwa` flag exists. [Source: https://github.com/phoenixframework/phoenix/blob/v1.8.3/installer/lib/phx_new/web.ex — `:html` template list, no manifest/sw] |
| `Plug.Static` + digest | `Plug.Static` `only:` lists the root paths served from `priv/static`; adding `"manifest.json"` + `"sw.js"` serves them at `/manifest.json` + `/sw.js`. `mix phx.digest` creates digested + `.gz` siblings and a `cache_manifest.json`, but the **originals remain** and are served at their literal paths — so referencing `/sw.js` + `/manifest.json` with literal paths (not `~p`) keeps the SW scope stable. `raise_on_missing_only: code_reloading?` means dev raises if a listed file is missing — create them. [Source: config/config.exs:74-81 (esbuild → `priv/static/assets/js`), https://hexdocs.pm/phoenix/Mix.Tasks.Phx.Digest.html, https://hexdocs.pm/plug/Plug.Static.html] |
| Chrome installability + SVG icon | Current Chrome accepts a single manifest icon with `sizes: "any"` + `type: "image/svg+xml"` for the installability criteria (a 192/512 raster pair is the legacy rule; SVG `any` satisfies it on modern Chrome). `display: "standalone"` + a `name` + `start_url` + an icon + HTTPS is the minimum. Verify on the target Android Chrome in Task 9; fall back to 192/512 PNGs (Task 4) only if it refuses. [Source: https://web.dev/articles/install-criteria] |
| CSRF on same-origin JSON POST | `protect_from_forgery` (`Plug.CSRFProtection`) verifies the token from the `x-csrf-token` header (or `_csrf_token` param) for non-GET requests when a session is present. The `csrfToken` is already read in `app.js` from the `meta[name=csrf-token]`. Put `protect_from_forgery` in the `:push` pipeline (after `fetch_session`) and send the header from the hook. [Source: https://hexdocs.pm/phoenix/Plug.CSRFProtection.html, lib/carwal_web/components/layouts/root.html.heex:6] |

### Previous story intelligence (1.3 + its reviews, 2026-07-07)

- `config/runtime.exs` has the empty-string-safe `read_env` helper + the named-error `Integer.parse` pattern + raise-on-missing-prod-env convention (`SECRET_KEY_BASE`, `SMTP_PASSWORD`, `PHX_HOST`). Task 1's VAPID block mirrors that exactly — no second idiom.
- Boot is deliberately strict in prod: missing/empty required env raises. VAPID keys follow the same contract; a missing `VAPID_PUBLIC_KEY`/`VAPID_PRIVATE_KEY` is a controlled failure, not a silent push-less deploy.
- `deploy.sh` rebuilds the image (`docker buildx build --platform linux/amd64`), ships, runs `Release.migrate()` post-load pre-restart, then `docker compose up -d`. A new migration (Task 2) + new dep (Task 1) therefore ship with a plain redeploy — no `deploy.sh` change needed. `~/carwal/.env.prod` is operator-created (`chmod 600`, never in git); VAPID keys go there.
- The `app` container healthcheck (`curl localhost:4000/health`) + Caddy `depends_on: app: condition: service_healthy` (Story 1.3 CodeRabbit follow-up) gate traffic on BEAM readiness — unaffected by this story.
- `static_paths/0` lives in `lib/carwal_web.ex` (not the endpoint) — Task 4 edits it there. `Phoenix.VerifiedRoutes` `statics:` reads the same list.
- `mix precommit` is the quality gate (101/101 green as of the 1.3 review); local PG on **5433**. New tests must keep it green; `deps.unlock --unused` is part of the gate (ex_nudge must be used).
- German strings through `gettext` from day one (config/config.exs `default_locale: "de"`); mirror the existing `Settings` LiveView German (`"Einstellungen"`, `"Abmelden"`, etc.) for the push page.
- Root `/` is still the Phoenix starter promo (Epic 2 builds the agenda) — `manifest.json` `start_url: "/"` lands a logged-in member there; known and accepted for 1.4.

### Project Structure Notes

- New: `lib/carwal/notifications/push_subscription.ex` (schema), `priv/repo/migrations/<ts>_create_push_subscriptions.exs`, `lib/carwal_web/controllers/push_controller.ex`, `lib/carwal_web/live/user_live/push_settings.ex`, `assets/js/push.js`, `priv/static/manifest.json`, `priv/static/sw.js`, `test/carwal/notifications_test.exs`, `test/carwal_web/controllers/push_controller_test.exs`, `test/carwal_web/live/user_live/push_settings_test.exs`.
- Modified: `mix.exs` (dep), `config/config.exs` (dev/test VAPID), `config/runtime.exs` (prod VAPID), `lib/carwal/notifications.ex` (stub → real context), `lib/carwal_web.ex` (`static_paths`), `lib/carwal_web/components/layouts/root.html.heex` (manifest + meta), `lib/carwal_web/router.ex` (`:push` pipeline + `/push` scope + `/users/push` live route), `assets/js/app.js` (register `Push` hook), `lib/carwal_web/live/user_live/settings.ex` (link to push page), `deploy/README.md` (VAPID env contract + redeploy note).
- NOT in this story: notification routing defaults (Epic 2/3), Oban (digest/reminders — Epic 3), iCal/IMAP ingestion, any auth code, any new hex deps beyond ex_nudge, PNG icon generation (only if the live smoke test requires it), backup/restore (1.5).
- Spine Structural Seed names `assets/` with `js hooks (geolocation, push)` — the push hook belongs in `assets/js/`, matching the existing `assets/js/app.js` + `assets/vendor/` layout. `deploy/` is untouched.

### References

- Epic + ACs: [Source: _bmad-output/planning-artifacts/epics.md#Story 1.4]
- AD-1 (Notifications owns `push_subscriptions`), AD-2 (web never touches Repo), AD-7 (only Notifications sends Web Push; minimal payloads), AD-13 (one SW + one push hook + per-device `(user_id, endpoint)` subs + one live_session/shell): [Source: _bmad-output/planning-artifacts/architecture/architecture-carwal-2026-07-05/ARCHITECTURE-SPINE.md#Invariants & Rules]
- Stack pin ex_nudge 1.0.x (VAPID): [Source: ARCHITECTURE-SPINE.md#Stack]
- FR11 (installable PWA, HTTPS-only, Android push) + FR14 (notification routing — foundation only here): [Source: epics.md#Functional Requirements]
- Previous story learnings + env/deploy contract: [Source: _bmad-output/implementation-artifacts/1-3-deploy-to-the-vps-over-https.md#Dev Notes, #Completion Notes List, #Change Log]
- Web-verified stack facts: hexdocs (ex_nudge `ExNudge`, `Plug.Static`, `Plug.CSRFProtection`, `Mix.Tasks.Phx.Digest`), MDN (PushManager.subscribe, PushSubscription), web.dev (install criteria), phoenixframework/phoenix v1.8.3 installer (no PWA scaffold), 2026-07-07.

## Dev Agent Record

### Agent Model Used

Gemini 3.5 Flash

### Debug Log References

None

### Completion Notes List

- Implemented Task 1: Added `ex_nudge` dependency (v1.0.2), generated dev/test VAPID keys, configured dev/test and prod environment configurations, and documented the env vars contract in `deploy/README.md`.
- Implemented Task 2: Created migration and schema `PushSubscription` with a unique constraint on `(user_id, endpoint)` to comply with AD-13.
- Implemented Task 3: Built context functions `register_subscription`, `list_subscriptions_for_user`, `unsubscribe`, `send_test_push`, and `send_test_push_to` in `Notifications` using `current_scope` as the first argument as required by project guidelines. Added expired subscription deletion on `:subscription_expired`.
- Implemented Task 4: Created PWA `manifest.json` and minimal service worker `sw.js` under `priv/static`. Registered them in `static_paths` and root layout head.
- Implemented Task 5: Added JSON controller `PushController` for subscribe/unsubscribe actions using scope-based authentication.
- Implemented Task 6: Created the `UserLive.PushSettings` LiveView page in German and linked it from the main settings page.
- Implemented Task 7: Implemented LiveView hook in `assets/js/push.js` with `urlBase64ToUint8Array` helper to handle browser base64 key decoding. Registered the hook in `app.js` and exported `csrfToken` for fetch calls.
- Implemented Task 8: Authored exhaustive test suite covering notifications schema, JSON endpoints, and the push settings LiveView. Overrode the skip-csrf flag in ConnCase tests to verify CSRF validation. Verified code format and quality gates via `mix precommit`.

### File List

- `mix.exs`
- `config/config.exs`
- `config/runtime.exs`
- `lib/carwal/notifications/push_subscription.ex`
- `priv/repo/migrations/20260707153203_create_push_subscriptions.exs`
- `lib/carwal/notifications.ex`
- `priv/static/manifest.json`
- `priv/static/sw.js`
- `lib/carwal_web.ex`
- `lib/carwal_web/components/layouts/root.html.heex`
- `lib/carwal_web/controllers/push_controller.ex`
- `lib/carwal_web/live/user_live/push_settings.ex`
- `lib/carwal_web/live/user_live/settings.ex`
- `lib/carwal_web/router.ex`
- `assets/js/push.js`
- `assets/js/app.js`
- `deploy/README.md`
- `test/carwal/notifications_test.exs`
- `test/carwal_web/controllers/push_controller_test.exs`
- `test/carwal_web/live/user_live/push_settings_test.exs`

### Change Log

- 2026-07-07: Story 1.4 created from epics + architecture spine. Status → ready-for-dev.
- 2026-07-07: Completed Tasks 1-8: added ex_nudge dependency, database migrations, Notifications context logic with current_scope, manifest + sw.js static assets, JSON controller, LiveView settings screen, JS hook, and comprehensive test suite. All tests passing green. Status → in-progress (halted for operator verification of Task 9).

## Status

done