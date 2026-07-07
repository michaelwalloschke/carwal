# Deferred Work

Items deferred from code reviews and other workflows. Each entry: where it came from, what it is, why deferred, and which story/action should pick it up.

## Deferred from: code review of story 1.1 (2026-07-06)

- `PHX_HOST` silently defaults to `example.com` in prod [`config/runtime.exs:56`] — phx.new default; `DATABASE_URL`/`SECRET_KEY_BASE` raise but `PHX_HOST` falls back silently, breaking redirects/CSRF origins/email links. Raise in prod block, mirroring the other two guards. → Story 1.3 (deploy to VPS).
- `PORT=""` (empty env var) crashes config load in every env [`config/runtime.exs:24`] — `System.get_env("PORT", "4000")` returns `""` when set-but-empty, `String.to_integer("")` raises before boot. Use `System.get_env("PORT") || "4000"`. → Story 1.3.
- `POOL_SIZE=""`/non-numeric crashes prod boot [`config/runtime.exs:39`] — same empty-string pattern; `|| "10"` guards `nil` only. → Story 1.3.
- `check_origin` not set in prod → LiveView WebSocket accepts any origin [`config/prod.exs`, `config/runtime.exs`] — phx.new default is `false`; cross-origin WS interactions possible. Set `check_origin: ["https://#{host}"]` in prod runtime block. → Story 1.3.
- `Phoenix.LiveDashboard.RequestLogger` plug mounted unguarded in prod [`lib/carwal_web/endpoint.ex:39`] — plug runs in prod; `?request_logger` param/cookie enables verbose per-request telemetry logging. Wrap in `if code_reloading? do ... end` or put behind admin auth. → Story 1.3.
- Prod mailer has no real adapter [`config/config.exs:47`, `config/prod.exs:26`] — global `Swoosh.Adapters.Local` + `config :swoosh, local: false` in prod: mail silently dropped (or raises) on first send. Configure SMTP/SES/Mailgun from env in prod block. → Story 1.2 (magic-link login needs mail).
- `cache_static_manifest` references gitignored build artifact [`config/prod.exs:8`] — `priv/static/cache_manifest.json` is build-generated; release built without `mix assets.deploy` crashes at boot. Ensure release pipeline runs `assets.deploy`, or guard with `File.exists?/1`. → Story 1.3.
- `force_ssl` trusts `X-Forwarded-Proto` unconditionally [`config/prod.exs:15`] — if endpoint reachable directly (no TLS-terminating proxy), client can spoof header to bypass SSL redirect / HSTS. Deploy only behind trusted reverse proxy (document) or remove `rewrite_on`. → Story 1.3.
- No health-check path exempt from `force_ssl` [`config/prod.exs:17`] — LB health probe over plain HTTP gets 301, marked unhealthy. Add `paths: ["/health"]` to `exclude` + a plain `/health` route. → Story 1.3.
- `tz` bundled tzdata staleness [`config/config.exs:19`] — tzdata has a validity cutoff; dates beyond it get stale DST transition rules → wrong UTC offset. Keep `tz` (and its tzdata) updated in CI; add a freshness check. → Ongoing maintenance.
- `ErrorHTML`/`ErrorJSON` return bare English status text [`lib/carwal_web/controllers/error_html.ex:22`] — 404/500 on HTML routes renders English "Not Found" etc. with `layout: false`; no German, no app chrome. Uncomment `embed_templates` + add German `404.html.heex`/`500.html.heex`. → When error pages are designed.
- `runtime.exs` unconditional endpoint port override clobbers test port 4002→4000 [`config/runtime.exs:23`] — `config` call runs for every env, deep-merges over `test.exs` port 4002. Suite unaffected today (`server: false`), but configured test port is silently wrong. Move inside `:prod` block or guard `if config_env() != :test`. → Cleanup.
- Nav shell is unmodified starter promo [`lib/carwal_web/components/layouts.ex:32`] — `Layouts.app` (AD-13 canonical shell) still links to phoenixframework.org/github, "Get Started" CTA, `v{Phoenix.vsn}` badge. Every later LiveView inherits it. Replace with CarWal nav. → Story 1.2+ (when real routes land).
- `ECTO_IPV6=true` with IPv4-only DB host [`config/runtime.exs:34`] — forces `socket_options: [:inet6]`, every checkout fails to connect. Document that `ECTO_IPV6` requires IPv6 DB reachability, or auto-detect via `:getaddrinfo`. → Cleanup.

## Deferred from: code review of story 1.1 — Chunk 2 (2026-07-06)

- `error_html_test`/`error_json_test` assert English `"Not Found"`/`"Internal Server Error"` [`test/carwal_web/controllers/error_html_test.exs:8,12`, `error_json_test.exs:5,10`] — pins the deferred English-error-page defect; tests will break the moment error pages are Germanified. Update both assertion pairs in the same change that Germanifies error pages. → When error pages are designed.
- `error_html_test`/`error_json_test` use `CarWalWeb.ConnCase` (starts SQL sandbox owner) despite calling `render` directly with no conn/DB [`test/carwal_web/controllers/error_*_test.exs:2`] — pure-render tests fail if PG is down. Switch to `use ExUnit.Case, async: true` (keep `import Phoenix.Template` in the HTML test) or split a `ViewCase` that doesn't start the sandbox. → Test cleanup.
- `data_case.ex` `errors_on/1` docstring example references `Accounts.create_user/1` which does not exist yet (Story 1.2's `phx.gen.auth` generates it) [`test/support/data_case.ex`] — phx.new default boilerplate; copy-paste users hit a compile error today. Swap to a generic changeset example or annotate "lands in Story 1.2". → Story 1.2.
- `page_controller_test` missing `async: true` [`test/carwal_web/controllers/page_controller_test.exs:2`] — safe for a static GET with no DB; currently serial via shared sandbox. Add `async: true` (after fixing the assertion regression). → Test cleanup.
- `DataCase.errors_on/1` calls `String.to_existing_atom/1` on interpolation keys before the `Keyword.get` fallback applies [`test/support/data_case.ex`] — raises `ArgumentError` on an unknown dynamic-key atom instead of falling back. Use `String.to_atom/1` (keys bounded by message templates, safe) or rescue → fallback. → Test cleanup.
- `Location` moduledoc matches AD-1 ("persists nothing") but omits the FR8 capability names (share-live-map, where-are-you) the Task 3 subtask lists [`lib/carwal/location.ex:3-5`] — AD-1 literal match; capability naming is FR-level. Elaborate when the context is implemented. → Stories 5.1/5.2.

## Deferred from: code review of story 1.1 — Re-review of patches (2026-07-06)

- `de/default.po` + `default.pot` lack `Content-Type: text/plain; charset=UTF-8` header [`priv/gettext/de/LC_MESSAGES/default.po`, `priv/gettext/default.pot`] — matches existing `errors.po` convention (also missing it); Elixir gettext runtime reads UTF-8 regardless. Only external GNU gettext tooling (`msgfmt`/`msgmerge`/PO editors) defaults to ASCII without it and may misread umlauts. Add `Content-Type` + `Content-Transfer-Encoding: 8bit` to all three files when external PO tooling is adopted. → When external PO tooling is introduced.
- Trailing whitespace on a blank line inside the inline theme `<script>` [`lib/carwal_web/components/layouts/root.html.heex:36`] — phx.new generated starter content; `mix format` does not clean inside `<script>` raw blocks. Replace with a truly empty line during a layout cleanup. → Layout cleanup.
- Inline theme `<script>` in `<head>` violates AGENTS.md "Never write inline `<script>` tags within templates" [`lib/carwal_web/components/layouts/root.html.heex:11-39`] — two-axis review (Standards) flagged it. The script runs pre-paint to set `data-theme` from `localStorage` and avoid FOUC; moving it to deferred `assets/js/app.js` satisfies the no-inline rule but reintroduces a flash-of-unstyled-content on every page load — a real UX regression, so the fix was **not** applied. phx.new 1.8.8 generator pattern. Revisit only if a non-inline pre-paint mechanism is adopted (e.g. a separate sync `<script src>` static file in `<head>`, or a server-rendered `data-theme` attribute from a cookie). → When a non-inline pre-paint theme mechanism is chosen.

## Deferred from: code review of story 1.2 (2026-07-07)

- No UI path to the login page for a logged-out user [`lib/carwal_web/router.ex:23`] — `/` is the starter promo without `Layouts.app` (no nav shell, no Anmelden link); every other route requires auth, so login is reachable only by typing `/users/log-in`. Already documented in the 1.2 Completion Notes. → Epic 2 (agenda LiveView replaces `/`).
- Login timing oracle [`lib/carwal_web/live/user_live/login.ex:72`] — seeded email = token insert + synchronous SMTP send before the flash renders; unseeded returns immediately. Response bytes identical (AC2 satisfied), response time discloses seeded addresses. Operator decision: accept for the household threat model (attacker only learns an email belongs to a family member). Fix would be async delivery via Task.Supervisor. → Revisit if the threat model changes (e.g. app opened beyond the family).

## Deferred from: code review of story 1.3 (2026-07-07)

- source_spec: `_bmad-output/implementation-artifacts/1-3-deploy-to-the-vps-over-https.md`
  summary: Print Docker compose logs on health check timeout in deploy.sh.
  evidence: If the container crashes on boot during deploy, the deploy script hangs for 120 seconds and then exits with timeout, without showing the crash traceback or logs of the failed container.

## Deferred from: code review of 1-3-deploy-to-the-vps-over-https.md (2026-07-07)

- **Health check check DNS Latency risk**: Polling `https://$CARWAL_DOMAIN/health` from the local machine is susceptible to DNS latency, which can cause the script to report a failed deployment even if the server is healthy.

## Deferred from: PR #12 `/review` pass 2 of story 1.3 (2026-07-07)

- `postgres:18` not pinned to minor/patch [`deploy/compose.yml`] — spec permits `:18`; floats within 18.x. Caddy pinned to `2.9-alpine` already. Pin `postgres:18.x` for reproducibility when a maintenance pass touches deploy. Low.
- `:health` pipeline accepts `["text","html","json"]` [`lib/carwal_web/router.ex:21`] — spec wanted minimal `:accepts`; "html" harmless for a probe (browser GET returns `ok` text). Narrow to `["json"]` on a cleanup pass. Nit.
- `HealthController` sets no `Content-Type` [`lib/carwal_web/controllers/health_controller.ex:7`] — `send_resp(conn, 200, "ok")` leaves default; probes don't care. Optional: `put_resp_content_type(conn, "text/plain")`. Nit.

## Deferred from: code review of story-1.4 (2026-07-07)

- source_spec: `_bmad-output/implementation-artifacts/1-4-pwa-install-push-foundation.md`
- `sw.js` notification-click focus logic is moot since push payload `data.url` is hardcoded to `'/'` [`priv/static/sw.js:8,18`] — real fix belongs with the notification-content stories that give pushes an actual target route. → Stories 3.3/3.4.
- No `pushsubscriptionchange` listener in `sw.js` to handle silent browser-side key rotation [`priv/static/sw.js`] — low-probability edge case, not exercised by any current flow.
- No `endpoint` length validation before insert (Postgres btree index row-size limit ~2704 bytes) [`lib/carwal/notifications/push_subscription.ex`] — real W3C push service endpoints are far under this in practice.
- `list_subscriptions_for_user/1` unbounded, no ordering/limit [`lib/carwal/notifications.ex:42`] — fine at family-app device-count scale (a handful of devices per user).
- `navigator.serviceWorker.ready` await has no timeout in `push.js` [`assets/js/push.js:40`] — hangs the enable-button flow silently if SW registration stalls; low-probability.
- `config/test.exs` uses one global `:web_push_client` stub for the whole suite instead of per-test override [`config/test.exs`] — works today since callers can pass `send_fun` directly; revisit if a test needs per-test failure injection.

## Deferred from: code review of story 1.3 — Pass 3 (`/bmad-code-review`, 2026-07-07)

- source_spec: `_bmad-output/implementation-artifacts/1-3-deploy-to-the-vps-over-https.md`
- db `env_file: .env.prod` injects app secrets + family PII into the postgres container env [`deploy/compose.yml:13-14`] — postgres only needs `POSTGRES_PASSWORD`; narrow on a secrets-hardening pass (requires choosing where the password lives: separate `db.env` vs interpolation from `~/carwal/.env`). Low (household threat model — operator already holds `.env.prod`).
- caddy `depends_on: app` short-form + `app` has no healthcheck [`deploy/compose.yml:42-43`] — Caddy 502s for the seconds BEAM takes to bind on restart. Add an app healthcheck + `condition: service_healthy` (needs choosing the mechanism — curl is not in the runner image). Low.
- `:health` pipeline `:accepts, ["text","html","json"]` 406s on strict `Accept` headers [`lib/carwal_web/router.ex:20-22`] — external monitors with `Accept: application/xml` see 406; deploy.sh curl sends `*/*` and passes. Already deferred as nit (Pass 2).
- `force_ssl` `exclude: paths: ["/health"]` is dead config [`config/prod.exs:17`] — deploy.sh polls https through Caddy (`x_forwarded_proto: https`, no redirect) and the app port is never published, so no plain-HTTP probe reaches the endpoint. Spec-required; keep, becomes live if a plain-HTTP LB probe is added. Low.
- `docker save | ssh docker load` ships an uncompressed ~200-400 MB image [`deploy/deploy.sh:17`] — gzip pipe (`docker save | gzip | ssh "gunzip | docker load"`) if ship time becomes painful; QEMU build dominates today. Low (perf).
- `no_mx_lookups: true` hardcoded, not tied to `SMTP_PORT` [`config/runtime.exs:136`] — correct for submission relays (587/465) but a future provider reached via MX would time out with the same symptom the fix prevented. Comment already documents the submission-relay assumption. Low (info).
- No SSH `ConnectTimeout`/`ServerAliveInterval` in deploy.sh [`deploy/deploy.sh`] — first-run host-key prompt blocks non-interactive/CI use; flaky network can hang the `docker save | ssh` pipe. Add `-o ConnectTimeout=10 -o ServerAliveInterval=15 -o StrictHostKeyChecking=accept-new` if deploy.sh moves to CI. Low.
- `docker save | ssh docker load` has no timeout [`deploy/deploy.sh:17`] — SSH drop mid-load can leave a partial image tagged `carwal:latest` → next `compose up` boots a corrupt image. Retag-on-success pattern (load to temp tag, tag latest only on full success). Low.
- Migration failure leaves `db` running → partial deploy state [`deploy/deploy.sh:30-33`] — running db, no app/caddy; a re-run's `--wait db` sees db healthy but migrations still broken. `trap '... compose down' ERR` or a README recovery note. Low.
- `POSTGRES_PASSWORD`/`DATABASE_URL` password mismatch not detected at db healthcheck [`deploy/compose.yml:22`] — `pg_isready -U carwal` uses peer auth, passes regardless of password; mismatch surfaces at migrate (auth failed, loud). Optional: `PGPASSWORD=$POSTGRES_PASSWORD psql -U carwal -d carwal -c 'select 1'` healthcheck. Low.
- Caddy LE rate-limit risk if DNS not pointed at the VPS on first deploy [`deploy/caddy/Caddyfile`] — `restart: unless-stopped` + ACME retries can hit the LE `new-order` limit (5/hour). README already lists DNS as a precondition; Caddy backs off. Low.
- Caddyfile `{$CARWAL_DOMAIN}` empty on manual `docker compose up` if `~/carwal/.env` is deleted [`deploy/caddy/Caddyfile:1`] — Caddy crash-loops with an unhelpful parse error. `{$CARWAL_DOMAIN:localhost}` env-default or a compose `.env` guard; README says do not delete `~/carwal/.env`. Low.