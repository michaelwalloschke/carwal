---
baseline_commit: 7ecb2ac60d6f8bee6582648a3b3401f05999b5b1
final_revision: 2b7a958055a99801e985a60849610f993f0f46b6
followup_review_recommended: false
---

# Story 1.3: Deploy to the VPS over HTTPS

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->
<!-- baseline_commit: to be stamped by dev-story at implementation start. The 1.2 code-review
     fixes (2026-07-07) were still uncommitted when this story was created — commit them on the
     1.2 branch first, then baseline 1.3 on the resulting mainline commit. -->

## Story

As the operator,
I want a scripted deploy that ships the app to the Hetzner VPS behind TLS,
so that the family reaches CarWal at its domain and every later deploy is one command.

## Acceptance Criteria

1. **Given** the VPS and domain exist (operator prerequisites: VPS provisioned, DNS A/AAAA pointing at it), **when** `deploy/deploy.sh` runs on the M1 Mac, **then** the image is built with `docker buildx --platform linux/amd64`, shipped via `docker save | ssh | docker load`, migrations run via `bin/carwal eval "CarWal.Release.migrate()"` **before** the app container restarts, **and** Docker Compose runs app + PostgreSQL + Caddy with automatic Let's Encrypt.
2. **Given** a deployed app, **when** the domain is opened via HTTP, **then** the request is redirected to HTTPS **and** the login page renders (check `/users/log-in` — the root `/` is still the starter promo until Epic 2).

## Tasks / Subtasks

- [x] Task 1: Generate release + Docker plumbing via `mix phx.gen.release --docker` (AC: 1)
  - [x] Run `mix phx.gen.release --docker`. It generates: `Dockerfile`, `.dockerignore`, `rel/overlays/bin/server` (+ `.bat`), `rel/overlays/bin/migrate` (+ `.bat`), and `lib/carwal/release.ex` with `migrate/0` + `rollback/2` (module `CarWal.Release` — matches the AC's eval call exactly). Verify all landed; do not hand-write what the generator writes.
  - [x] Builder stage: add `ENV ERL_FLAGS="+JMsingle true"` to the **builder** stage of the generated Dockerfile. QEMU user-mode emulation (what buildx uses on the M1 for linux/amd64) cannot handle the BEAM JIT's dual-mapped W^X memory; this flag is the documented fix. Builder-only — the shipped release runs natively on amd64 and keeps the normal JIT.
  - [x] Verify the runner stage installs `ca-certificates` (the 1.8.8 template does — needed for SMTP TLS verification, Task 3) and that the Dockerfile runs `mix assets.deploy` (generates `priv/static/cache_manifest.json`, which `config/prod.exs:8` requires at boot — closes the 1.1-deferred `cache_static_manifest` item by construction).
  - [x] Add `CarWal.Release.seed/0` next to the generated `migrate/0`: `load_app()` then `Ecto.Migrator.with_repo(CarWal.Repo, fn _ -> Code.eval_file(Path.join([:code.priv_dir(:carwal), "repo", "seeds.exs"])) end)`. Releases have no Mix, so `mix run priv/repo/seeds.exs` does not exist in prod — this is the only way to seed the family. `priv/` ships inside the release, and `seeds.exs` (Story 1.2) already refuses placeholder/empty emails when a real mail adapter is configured.
  - [x] Do NOT add any deps. `phx.gen.release` generates files only; Oban/ical/yugo/ex_nudge/mistral stay out until their stories.
- [x] Task 2: Harden prod runtime config — closes five 1.1-deferred items (AC: 1, 2)
  - [x] `PHX_HOST`: replace the silent `|| "example.com"` fallback with a raise, mirroring `DATABASE_URL`/`SECRET_KEY_BASE` (wrong host breaks redirects, CSRF origins, and every magic-link URL in mail).
  - [x] Reuse the `read_env` empty-string-safe helper that the 1.2 review added to `config/runtime.exs` — hoist it above the endpoint block, extend it to support an optional default fallback value (e.g., `read_env.(name, default)`), and route `PORT`, `POOL_SIZE`, `PHX_HOST`, and `DATABASE_URL` reads through it (`PORT=""` currently crashes `String.to_integer/1` in **every** env, `POOL_SIZE=""` in prod). Parse `PORT`/`POOL_SIZE` with the same named-error `Integer.parse` pattern the SMTP_PORT fix established.
  - [x] Move the unconditional top-of-file endpoint `port:` override (`config/runtime.exs:23-24`) inside a `if config_env() != :test` guard — it currently clobbers the test port 4002→4000 (1.1-deferred cleanup; you are touching these lines anyway).
  - [x] Set `check_origin: ["https://#{host}"]` on the endpoint in the prod block (explicit beats relying on the default-`true`-derives-from-host behavior; the 1.1 review flagged the phx.new default `false` in dev as prod risk).
  - [x] Add a one-line comment at `ECTO_IPV6` noting it requires IPv6 reachability of the DB host (deferred doc item; the compose DB is reached by service name, leave the var unset in `.env.prod`).
- [x] Task 3: SMTP TLS verification — the first real magic-link mail must not be MITM-able (AC: 2, NFR1)
  - [x] gen_smtp (1.3.0) client defaults do **not** verify server certificates (`tls_options` has no `verify`/`cacerts`), and since OTP 26 the ssl client requires explicit cacerts for verification to succeed. Add to the prod `CarWal.Mailer` config in `config/runtime.exs`: `tls_options: [verify: :verify_peer, cacerts: :public_key.cacerts_get(), server_name_indication: String.to_charlist(smtp_host), depth: 3]` (bind `smtp_host` once; it already defaults to `"smtp.mailbox.org"`). `:public_key.cacerts_get()` reads the OS trust store — present in the runner image via `ca-certificates` (Task 1).
  - [x] Keep `ssl: false, tls: :always` (STARTTLS on 587) exactly as-is; only the verification options are new. _(Pass 3 note: `no_mx_lookups: false → true` was also set during Task 6 — a justified bug fix, not a verification option; see Review Findings Pass 3 + Pass 2 Completion Notes.)_
- [x] Task 4: Endpoint hardening + health check (AC: 2)
  - [x] Wrap the `Phoenix.LiveDashboard.RequestLogger` plug in `lib/carwal_web/endpoint.ex` in `if code_reloading? do ... end` (or guard on `:dev_routes`) — it currently runs in prod and `?request_logger` enables verbose per-request telemetry logging (1.1-deferred).
  - [x] Add a `/health` route: plain controller returning 200 `"ok"`, no DB touch, no auth, through a minimal pipeline (`:accepts` only — it must not redirect or set cookies). Uncomment `paths: ["/health"]` in the `force_ssl` `exclude` in `config/prod.exs` so a plain-HTTP probe is not 301'd (1.1-deferred; also gives `deploy.sh` its post-restart readiness check).
  - [x] `force_ssl` stays with `rewrite_on: [:x_forwarded_proto]` — Caddy sets that header and strips incoming spoofs. This trust is safe **only** because the app port is never published on the host (Task 5 compose rule); its remaining value over Caddy's own redirect is HSTS.
- [x] Task 5: `deploy/` artifacts — compose.yml, Caddyfile, deploy.sh, env file contract (AC: 1)
  - [x] `deploy/compose.yml`, three services (spine Structural Seed):
    - `app`: the shipped image; `env_file: .env.prod`; **no `ports:` mapping** (compose-network-internal only — load-bearing for the `x_forwarded_proto` trust, Task 4); `depends_on` db; restart `unless-stopped`.
    - `db`: `postgres:18` — **volume MUST be `pgdata:/var/lib/postgresql`**, not `/var/lib/postgresql/data`: the official 18 image moved the `VOLUME` mount point and defaults `PGDATA` to `/var/lib/postgresql/18/docker`; the old path silently fails to persist. Configure environment: `POSTGRES_USER: carwal`, `POSTGRES_DB: carwal`, and `POSTGRES_PASSWORD` from the env file. No host port mapping (5433 collision risk is local-dev-only, but same rule: internal).
    - `caddy`: `caddy:latest` (or pinned current); ports `80:80`, `443:443`, `443:443/udp` (HTTP/3); volumes `caddy_data:/data` (**must persist** — Let's Encrypt certs/keys; losing it on redeploy burns LE rate limits), `caddy_config:/config`, and mount the config **directory** `./caddy:/etc/caddy` (single-file bind mounts break Caddy's graceful reload on inode change). Pass `CARWAL_DOMAIN` into the caddy service (`environment:` or the shared env file) — the Caddyfile references it as `{$CARWAL_DOMAIN}`.
    - Declare the named volumes (`pgdata`, `caddy_data`, `caddy_config`) in a top-level `volumes:` section at the bottom of the compose file.
  - [x] `deploy/caddy/Caddyfile`: `{$CARWAL_DOMAIN} { reverse_proxy app:4000 }` — that is the whole file. Automatic HTTPS + HTTP→HTTPS redirect are Caddy defaults for a domain site address; `X-Forwarded-Proto` is set automatically. Optionally add the HSTS header here instead of relying on `force_ssl` for it.
  - [x] `deploy/deploy.sh` (bash, `set -euo pipefail`), parameterized by `CARWAL_HOST` (SSH target) + `CARWAL_DOMAIN`:
    1. `docker buildx build --platform linux/amd64 --load -t carwal:latest .` (the platform flag is **load-bearing** — BEAM releases are not arch-portable; `--load` because buildx defaults to not exporting to the local daemon).
    2. `docker save carwal:latest | ssh $CARWAL_HOST docker load` (registry-free per spine).
    3. `scp`/rsync `deploy/compose.yml` + `deploy/caddy/` to the VPS deploy dir.
    4. Robust database startup and migrations (prevents connection crashes during initialization): start the `db` service alone first via `ssh $CARWAL_HOST "docker compose up -d db"`, poll database readiness inside a loop via `ssh $CARWAL_HOST "until docker compose exec -T db pg_isready -U carwal -d carwal; do sleep 1; done"`, and then run the migrations via `ssh $CARWAL_HOST "docker compose run --rm app bin/carwal eval 'CarWal.Release.migrate()'"`. _(Pass 3 note: the shipped script uses `docker compose up -d --wait --wait-timeout 60 db` instead of the `pg_isready` poll loop — behaviorally equivalent, blocks until the compose healthcheck passes; see commit 2b7a958 + Review Findings Pass 3.)_
    5. `ssh $CARWAL_HOST "docker compose up -d"` to start the remaining services (app, caddy) and poll `https://$CARWAL_DOMAIN/health` until 200 (fail the script after a timeout).
  - [x] Document (comment header in deploy.sh or `deploy/README.md`): first-run-only steps — create `.env.prod` on the VPS (`chmod 600`, never in git), run the database seeding command `docker compose run --rm app bin/carwal eval 'CarWal.Release.seed()'` after the first migrate, and the full env var contract: `DATABASE_URL` (points at `db` service: `ecto://carwal:<pass>@db/carwal`), `SECRET_KEY_BASE` (`mix phx.gen.secret`), `PHX_HOST`, `SMTP_USERNAME`, `SMTP_PASSWORD`, optional `SMTP_HOST`/`SMTP_PORT`/`MAIL_FROM`, `FAMILY_OPERATOR_NAME/EMAIL`, `FAMILY_MOTHER_NAME/EMAIL`, `FAMILY_DAUGHTER_NAME/EMAIL`, `POSTGRES_PASSWORD`. Note which ones raise at boot when missing/empty (DATABASE_URL, SECRET_KEY_BASE, PHX_HOST after Task 2, SMTP_USERNAME/PASSWORD) and that the seed **refuses** placeholder/empty family emails against the real SMTP adapter (Story 1.2 guard — that refusal is correct behavior, not a bug).
  - [x] `PHX_SERVER=true` belongs in `.env.prod` (any non-empty value enables the server; the `bin/server` overlay sets it too, but compose runs `bin/carwal start` semantics via the image CMD `/app/bin/server` — verify the generated CMD and keep one mechanism).
- [x] Task 6: First deploy + end-to-end verification (AC: 1, 2)
  - [x] Preconditions (operator, not the loop — HALT and ask if missing): Hetzner VPS reachable over SSH with Docker + Compose installed, DNS A/AAAA for the domain pointing at it, mailbox.org SMTP credentials at hand. — VPS `carwal.cloud` (152.239.122.139): Docker 29.6.1 + Compose v5.3.0 installed, SSH key auth enabled, DNS A/AAAA verified. SMTP provider is Posteo (`posteo.de:587` STARTTLS), not mailbox.org.
  - [x] Run `deploy/deploy.sh` for real. Verify: `curl -I http://<domain>` → 301/308 to HTTPS; `https://<domain>/users/log-in` renders the German login page; `https://<domain>/health` → 200; valid LE certificate. — deploy.sh exit 0; `308→https`; `/health=200 ok`; `/users/log-in=200` German (`Anmelden`/`Anmeldelink`/`E-Mail`); LE cert `CN=carwal.cloud` valid Jul 7 → Oct 5 2026.
  - [x] Send a real magic link to the operator's seeded address and complete one login on a phone — this exercises the whole NFR1 mail path (SMTP + TLS verify, Task 3) and the 10-year session cookie over HTTPS for the first time. — magic-link mail delivered via Posteo STARTTLS (`ESMTPSA`, DKIM/SPF/DMARC pass, TLS 1.3); operator clicked the link on a phone and logged in (10-year session cookie over HTTPS). Required a `no_mx_lookups: true` fix (see Pass 2 Completion Notes) — the first attempt MX-resolved `posteo.de` → `mx04.posteo.de` (inbound MX) and timed out.
  - [x] Record the deploy runbook result + any VPS one-time setup performed in `deploy/README.md`. Restore/backup is **not** this story (1.5); do not create restic plumbing. — "First Deploy Record (2026-07-07)" section added to `deploy/README.md` (operator setup, deploy.sh result, AC2 verification table, seed, magic-link smoke-test steps, no_mx_lookups fix).
- [x] Task 7: Tests + verification (AC: 1, 2)
  - [x] Test for `/health`: plain `get(conn, "/health")` → 200 `"ok"` (controller test; no LiveView, no fixture).
  - [x] `mix precommit` green (compile --warnings-as-errors, deps.unlock --unused, format, test) against local `carwal-pg` on 5433. The runtime.exs changes (Task 2) must not break test env — the port-override guard is exactly for that.
  - [x] `docker buildx build --platform linux/amd64` completes locally (slow under QEMU — expect minutes, that is normal, not a hang).

### Review Findings

- [x] **Patch** CARWAL_DOMAIN is not passed to the remote environment in deploy.sh [deploy/deploy.sh]
- [x] **Patch** Infinite loop / lack of timeout in database readiness check in deploy/deploy.sh [deploy/deploy.sh]
- [x] **Patch** Potential directory nesting when copying caddy config in deploy/deploy.sh [deploy/deploy.sh]
- [x] **Patch** Health check route /health does not use a minimal pipeline (:accepts check) [lib/carwal_web/router.ex]
- [x] **Patch** Mutable Caddy image tag [deploy/compose.yml]
- [x] **Defer** Health check check DNS Latency risk [deploy/deploy.sh] — deferred, pre-existing

### Review Findings — Pass 2 (PR #12 `/review`, 2026-07-07)

- [x] **Patch** CARWAL_DOMAIN not persisted on VPS for manual compose commands [deploy/deploy.sh, deploy/README.md] — deploy.sh now writes `CARWAL_DOMAIN` to `~/carwal/.env` (compose auto-loads it for interpolation + `environment:` passthrough); README documents that manual `docker compose restart/up` no longer need the var prefixed.
- [x] **Patch** deploy.sh assumes CWD = repo root [deploy/deploy.sh] — added `cd "$(dirname "$0")/.."` after the arg check so `scp deploy/...` paths and the build context resolve from any CWD.
- [x] **Patch** PORT ↔ Caddy `app:4000` coupling undocumented [deploy/README.md] — README env contract now lists `PORT` with "leave unset" warning (Caddyfile hardcodes `reverse_proxy app:4000`).
- [ ] **Defer** `postgres:18` not pinned to minor/patch [deploy/compose.yml] — spec permits `:18`; reproducibility would pin `18.x`. Deferred (low).
- [ ] **Nit** `:health` pipeline accepts `["text","html","json"]` [lib/carwal_web/router.ex] — spec wanted minimal `:accepts`; "html" harmless for a probe. Deferred (nit).
- [ ] **Nit** `HealthController` sets no Content-Type [lib/carwal_web/controllers/health_controller.ex] — probes don't care. Deferred (nit).

### Review Findings — Pass 3 (`/bmad-code-review`, 2026-07-07)

Three adversarial layers (Blind Hunter, Edge Case Hunter, Acceptance Auditor) over `git diff 7ecb2ac` (review_mode=full). Triage: 0 decision-needed, 12 patch, 12 defer, 13 dismissed.

- [x] **Patch** `Release.seed/0` swallows `with_repo` failure → `bin/carwal eval CarWal.Release.seed()` exits 0 on a seed/DB failure, operator believes family is seeded [lib/carwal/release.ex:16-22] — fixed: pattern-match `{:ok, _, _} =` mirroring `migrate/0`/`rollback/2`.
- [x] **Patch** `PORT`/`POOL_SIZE`/`SMTP_PORT` `Integer.parse` accepts negative/out-of-range (`-1`, `0`, `65536`, `99999`) → named raise never fires, cryptic bind/SMTP failure instead [config/runtime.exs:29-32,50-54,108-112] — fixed: `when p >= 1 and p <= 65535` (ports) / `when size >= 1` (POOL_SIZE) guards; error messages name the range.
- [x] **Patch** Health-poll timeout counts sleep only, not curl `--max-time 5` → "timed out after 120s" message is false (real wall-clock ~280s worst case) [deploy/deploy.sh:39-56] — fixed: wall-clock `deadline=$(( $(date +%s) + timeout ))` compared each iteration.
- [x] **Patch** `CARWAL_DOMAIN` unvalidated → value with `'`/`;`/backtick/space injects into the remote `.env` write and the unquoted `CARWAL_DOMAIN=$CARWAL_DOMAIN` on every remote `docker compose` command; also breaks Caddyfile parse [deploy/deploy.sh:24,30,33,36] — fixed: `case "$CARWAL_DOMAIN" in *[!A-Za-z0-9.-]*) exit 1;; esac` charset guard at entry.
- [x] **Patch** `http_code=$(curl ... || echo "failed")` yields `000failed` on connection failure → garbled log line, future `case`-on-code would miss [deploy/deploy.sh:44] — fixed: `$(curl ... || true)`; curl's `-w` already prints `000` on failure.
- [x] **Patch** `Auto Run Result` block contradicts the Review Findings sections (says "Patches applied: 0" while Pass 1+2 list 8 patched findings) [story .md:253-256] — fixed: breakdown now points at the Review Findings sections (Pass 1+2: 8 patches; Pass 3: 12 patches + 12 defers + 13 dismissed).
- [x] **Patch** `PHX_SERVER=true` redundantly recommended in README env contract — the `bin/server` overlay + image CMD already set it; spec said keep one mechanism [deploy/README.md:25] — fixed: README now says `PHX_SERVER` is optional (overlay + CMD set it), explicit set harmless but redundant.
- [x] **Patch** No log rotation on `app`/`db` (default `json-file`, unbounded) → crash loop / verbose logger fills the small VPS disk [deploy/compose.yml] — fixed: `x-logging` anchor (`json-file`, `max-size: 10m`, `max-file: 3`) applied to `app` + `db`.
- [x] **Patch** `docker compose up -d --wait db` has no `--wait-timeout` → db restart loop (bad data dir, OOM) hangs the script indefinitely [deploy/deploy.sh:30] — fixed: `--wait --wait-timeout 60 db`.
- [x] **Patch** `.env.prod` missing on VPS not detected until `compose up` — wastes the full QEMU build + ship before a loud failure; fail-fast before the local build [deploy/deploy.sh] — fixed: `ssh "$CARWAL_HOST" "test -f ~/carwal/.env.prod"` as the first remote step, before the local build.
- [x] **Patch** Spec Task 3 text still says "only the verification options are new" — `no_mx_lookups: false → true` was also set (justified bug fix, see Pass 2 Completion Notes); reconcile the subtask text [story .md:43] — fixed: appended a Pass 3 note to the Task 3 subtask line recording the `no_mx_lookups` change.
- [x] **Patch** Spec Task 5 step 4 text still prescribes the `pg_isready` poll loop — the script uses `docker compose up -d --wait db` (behaviorally equivalent, commit 2b7a958); reconcile the subtask text [story .md:59] — fixed: appended a Pass 3 note to the Task 5 step 4 line recording the `--wait` mechanism.
- [x] **Defer** db `env_file: .env.prod` injects `SECRET_KEY_BASE`/`SMTP_PASSWORD`/`DATABASE_URL`/`FAMILY_*_EMAIL` PII into the postgres container env (visible via `docker inspect`); postgres only needs `POSTGRES_PASSWORD` — narrow on a secrets-hardening pass (requires choosing where the password lives: separate `db.env` vs interpolation) [deploy/compose.yml:13-14]
- [x] **Defer** caddy `depends_on: app` short-form + `app` has no healthcheck → Caddy 502s for the seconds BEAM takes to bind on restart; add app healthcheck + `condition: service_healthy` (needs choosing the healthcheck mechanism — curl not in runner image) [deploy/compose.yml:42-43]
- [x] **Defer** `:health` pipeline `:accepts, ["text","html","json"]` 406s on strict `Accept` headers (external monitors with `Accept: application/xml`); deploy.sh curl sends `*/*` so passes — already deferred as nit [lib/carwal_web/router.ex:20-22]
- [x] **Defer** `force_ssl` `exclude: paths: ["/health"]` is dead config — deploy.sh polls https through Caddy (`x_forwarded_proto: https`, no redirect) and the app port is never published, so no plain-HTTP probe reaches the endpoint; spec-required, keep, becomes live if a plain-HTTP LB probe is added [config/prod.exs:17]
- [x] **Defer** `docker save | ssh docker load` ships an uncompressed ~200-400 MB image; gzip pipe if ship time becomes painful (QEMU build dominates today) [deploy/deploy.sh:17]
- [x] **Defer** `no_mx_lookups: true` hardcoded, not tied to `SMTP_PORT` — correct for submission relays (587/465) but a future provider reached via MX would time out with the same symptom; comment already documents the submission-relay assumption [config/runtime.exs:136]
- [x] **Defer** No SSH `ConnectTimeout`/`ServerAliveInterval`; first-run host-key prompt blocks non-interactive/CI use — add `-o` opts if deploy.sh moves to CI [deploy/deploy.sh]
- [x] **Defer** `docker save | ssh docker load` has no timeout; SSH drop mid-load can leave a partial image tagged `carwal:latest` → boot crash; retag-on-success pattern [deploy/deploy.sh:17]
- [x] **Defer** Migration failure leaves `db` running → partial deploy state (running db, no app/caddy); trap-based teardown or README recovery note [deploy/deploy.sh:30-33]
- [x] **Defer** `POSTGRES_PASSWORD`/`DATABASE_URL` password mismatch not detected at db healthcheck (`pg_isready -U carwal` uses peer auth, passes regardless); migrate is the real auth gate and fails loudly — optional psql-based healthcheck [deploy/compose.yml:22]
- [x] **Defer** Caddy LE rate-limit risk if DNS not pointed at the VPS on first deploy (restart policy + ACME retries); README already lists DNS as a precondition, Caddy backs off [deploy/caddy/Caddyfile]
- [x] **Defer** Caddyfile `{$CARWAL_DOMAIN}` empty on manual `docker compose up` if `~/carwal/.env` is deleted → Caddy crash-loops; `{$CARWAL_DOMAIN:localhost}` default or .env guard — README says do not delete `~/carwal/.env` [deploy/caddy/Caddyfile:1]

## Dev Notes

### Critical guardrails (read before coding)

- **The platform flag is load-bearing.** BEAM releases embed ERTS for the build platform — an arm64 image on the amd64 VPS dies instantly. Every build goes through `docker buildx build --platform linux/amd64` in `deploy.sh`; never `docker build` on the M1 directly. And builds under QEMU need `ERL_FLAGS="+JMsingle true"` in the builder stage or the compiler segfaults (dual-mapped JIT memory vs QEMU).
- **PostgreSQL 18 changed the Docker volume contract.** Mount `/var/lib/postgresql` (image `VOLUME` since 18; `PGDATA` defaults to `/var/lib/postgresql/18/docker`). The pre-18 `/var/lib/postgresql/data` path in old compose examples will not persist data on 18. Local dev `carwal-pg` on 5433 is unaffected.
- **App and DB ports are never published on the host.** Only Caddy exposes 80/443(+udp). This is what makes `force_ssl`'s `x_forwarded_proto` trust safe (Caddy overwrites incoming forwarded headers) and keeps the enumeration-throttled login POST (1.2 review) as the only public write path.
- **The first real mail leaves the box in this story.** Until now every magic link landed in `Swoosh.Adapters.Local`/`Test`. gen_smtp does not verify TLS by default — Task 3's `tls_options` are a security fix, not an option. NFR1: relay stays mailbox.org/Posteo; never a non-EU mail SaaS.
- **Releases have no Mix.** No `mix ecto.migrate`, no `mix run seeds.exs` on the VPS. Everything goes through `bin/carwal eval` against `CarWal.Release` (`migrate/0` generated, `seed/0` added in Task 1). Migrations run post-image-load, pre-restart (spine).
- **Seeds guard is a feature.** `priv/repo/seeds.exs` (1.2) raises when a real mail adapter meets placeholder/empty family emails. If the first `Release.seed()` raises, the fix is exporting real `FAMILY_*_EMAIL` values in `.env.prod` — not weakening the guard.
- **One environment.** Prod on the VPS + local dev. No staging, no registry, no CI deploy — `deploy.sh` from the M1 is the whole pipeline (PRD decision; keep it boring).
- **Do not touch auth/login code.** 1.2 is done and reviewed (no-JS fallback, throttle, no-enumeration). This story only changes config, endpoint plumbing, release plumbing, and `deploy/`.
- **AGENTS.md CarWal note applies:** no registration or password routes exist; nothing in this story reintroduces them.
- **Errors convention:** anything added to contexts returns `{:ok, _} | {:error, _}`; `Release.migrate/seed` may raise (ops entry points, controlled failure is the contract there).
- **German UI (NFR3):** `/health` returns plain `"ok"` (machine endpoint, exempt); any user-visible string added elsewhere goes through the established German patterns.

### Verified stack facts (researched 2026-07-07; hexdocs / official images / Erlang docs)

| Item | Fact |
| --- | --- |
| `phx.gen.release --docker` (1.8.8) | Generates `Dockerfile` (builder `hexpm/elixir:<ver>-erlang-<ver>-debian-trixie-*-slim`, runner `debian:trixie-*-slim` with `libstdc++6 openssl libncurses6 locales ca-certificates`, runs as `nobody`, `CMD ["/app/bin/server"]`), `.dockerignore`, `rel/overlays/bin/{server,migrate}`, `lib/carwal/release.ex` (`CarWal.Release.migrate/0`, `rollback/2` via `Ecto.Migrator`). [Source: https://hexdocs.pm/phoenix/Mix.Tasks.Phx.Gen.Release.html, phoenix v1.8.8 templates] |
| Release env contract | `PHX_SERVER` (any non-empty value → `server: true`; `bin/server` overlay exports it), `DATABASE_URL` + `SECRET_KEY_BASE` raise when missing, `PHX_HOST` currently defaults to `example.com` (Task 2 makes it raise), `PORT` default 4000, binds `::` dual-stack. [Source: config/runtime.exs (generated), https://hexdocs.pm/phoenix/releases.html] |
| QEMU × BEAM JIT | OTP 25+ JIT uses dual-mapped W^X memory; QEMU user-mode emulation cannot handle it; `erl` flag `+JMsingle true` disables dual mapping. Set via `ERL_FLAGS` in the builder stage only (Livebook does the same). Builds are slow under emulation — expected. [Source: https://www.erlang.org/doc/apps/erts/erl_cmd.html, livebook-dev/livebook Dockerfile] |
| Caddy | Site address = domain → automatic HTTPS with Let's Encrypt **and** HTTP→HTTPS redirect by default. `reverse_proxy app:4000` sets `X-Forwarded-{For,Proto,Host}` and drops incoming values (anti-spoofing). Needs 80, 443, 443/udp; persistent `caddy_data:/data` (certs/keys) + `caddy_config:/config`; mount the config directory, not the single file. [Source: https://caddyserver.com/docs/automatic-https, https://hub.docker.com/_/caddy] |
| PostgreSQL 18 image | Current tag `postgres:18.4` (Debian trixie base). **Volume mount point moved to `/var/lib/postgresql`** (was `/var/lib/postgresql/data` ≤17); `PGDATA` default `/var/lib/postgresql/18/docker`. Env vars unchanged (`POSTGRES_PASSWORD` etc.). [Source: https://hub.docker.com/_/postgres] |
| `force_ssl`/`check_origin` behind Caddy | `force_ssl` is compile-time (`prod.exs`), forwards to `Plug.SSL`; `rewrite_on: [:x_forwarded_proto]` required behind a TLS-terminating proxy or every request redirect-loops. `check_origin` default `true` validates against the endpoint `:host` — correct once `PHX_HOST` is right; explicit `["https://<host>"]` allowed. `url: [host:, port: 443, scheme: "https"]` controls generated URLs only. [Source: https://hexdocs.pm/plug/Plug.SSL.html, https://hexdocs.pm/phoenix/Phoenix.Endpoint.html] |
| gen_smtp TLS | gen_smtp 1.3.0 client default `tls_options` = TLS versions only — **no `verify`, no `cacerts`**; OTP 26+ ssl requires explicit `cacerts`/`cacertfile` for verification. Fix: `tls_options: [verify: :verify_peer, cacerts: :public_key.cacerts_get(), server_name_indication: <charlist host>, depth: 3]`. `:public_key.cacerts_get()` needs the OS `ca-certificates` (in the runner image). Swoosh SMTP needs no API client (`config :swoosh, api_client: false` fine; prod.exs already sets Req — harmless, unused by SMTP). [Source: gen_smtp_client.erl defaults (vendored 1.3.0), https://www.erlang.org/doc/apps/ssl/ssl.html, https://hexdocs.pm/swoosh/Swoosh.Adapters.SMTP.html] |
| Ship path | `docker save carwal:latest \| ssh <host> docker load` — registry-free per spine/addendum; `buildx --load` needed first (buildx does not export to the local daemon by default). [Source: addendum.md#Deployment, docker buildx docs] |

### 1.1-deferred items this story closes (from deferred-work.md)

`PHX_HOST` silent default → raise · `PORT=""` crash → `read_env` · `POOL_SIZE=""` crash → `read_env` · `check_origin` unset → explicit https origin · `RequestLogger` unguarded in prod → guard · `cache_static_manifest` boot crash risk → Dockerfile runs `assets.deploy` · `force_ssl` header trust → documented + app port never published · no `/health` exempt path → route + exclude. (`ECTO_IPV6` gets a doc comment; the test-port-clobber cleanup rides along in Task 2.)

### Previous story intelligence (1.2 + its 2026-07-07 review)

- `config/runtime.exs` already has the empty-string-safe `read_env` helper (SMTP block) and named-error `Integer.parse` for `SMTP_PORT` — Task 2 extends that pattern instead of inventing a second one.
- Boot behavior is deliberately strict: missing/empty `SMTP_USERNAME`/`SMTP_PASSWORD` raise in prod. The deploy env file must be complete before first boot; that is the designed controlled failure.
- Seeds are idempotent (safe to re-run `Release.seed()`) and refuse placeholders against real SMTP — tested in `test/carwal/seeds_test.exs`.
- The login page is `/users/log-in` (LiveView + no-JS POST fallback). Root `/` is still the Phoenix starter promo without the nav shell (deferred to Epic 2) — AC2's "login page renders" must be checked on `/users/log-in`, and a logged-out member has no clickable path to it yet (known, accepted).
- Magic-link requests are throttled to one live link per member per 15-min window — do not "fix" a seemingly missing second mail during smoke testing.
- Session cookie `max_age` is 10 years (`@max_cookie_age_in_days 3650`); first HTTPS deploy is the first time the cookie is actually `secure`.
- `mix precommit` is the quality gate (100 tests green as of the 1.2 review); local PG runs on **5433**.

### Project Structure Notes

- New: `Dockerfile`, `.dockerignore`, `rel/overlays/bin/{server,migrate}` (generator), `lib/carwal/release.ex` (generator + hand-added `seed/0`), `deploy/compose.yml`, `deploy/caddy/Caddyfile`, `deploy/deploy.sh`, `deploy/README.md`, `lib/carwal_web/controllers/health_controller.ex` (or a plug-level route — pick the smallest thing that returns 200 without touching the browser pipeline).
- Modified: `config/runtime.exs` (Task 2 + 3), `config/prod.exs` (health exclude), `lib/carwal_web/endpoint.ex` (RequestLogger guard), `lib/carwal_web/router.ex` (/health).
- NOT in this story: restic/backup (`deploy/restore.sh` is 1.5), PWA manifest/service worker (1.4), any auth code, any new hex deps.
- Spine Structural Seed names `deploy/` with `compose.yml`, `Caddyfile`, `deploy.sh` — keep those exact names (Caddyfile lives in `deploy/caddy/` for the directory-mount rule; that refinement is deliberate).

### References

- Epic + ACs: [Source: _bmad-output/planning-artifacts/epics.md#Story 1.3]
- Deployment shape, registry-free ship, buildx flag: [Source: _bmad-output/planning-artifacts/architecture/architecture-carwal-2026-07-05/ARCHITECTURE-SPINE.md#Structural Seed] [Source: _bmad-output/planning-artifacts/prds/prd-carwal-2026-07-05/addendum.md#Deployment]
- NFR1 sovereignty (Hetzner EU, sovereign mailbox): [Source: _bmad-output/planning-artifacts/prds/prd-carwal-2026-07-05/prd.md#NFR1] [Source: epics.md#NonFunctional Requirements]
- Deferred items closed here: [Source: _bmad-output/implementation-artifacts/deferred-work.md — items tagged "→ Story 1.3"]
- Previous story learnings: [Source: _bmad-output/implementation-artifacts/1-2-magic-link-login-for-seeded-members.md#Completion Notes List, #Review Findings]
- Web-verified stack facts: hexdocs (phx.gen.release, releases, Plug.SSL, Swoosh SMTP), erlang.org (erl `+JMsingle`, ssl defaults), hub.docker.com (postgres 18 volume change, caddy), 2026-07-07.

## Review Triage Log

### 2026-07-07 — Review pass
- intent_gap: 0
- bad_spec: 0
- patch: 0
- defer: 1
- reject: 0
- addressed_findings:
  - none

### 2026-07-07 — Review pass 2 (PR #12 `/review`)
- intent_gap: 0
- bad_spec: 0
- patch: 3
- defer: 3
- reject: 0
- addressed_findings:
  - CARWAL_DOMAIN persistence on VPS (patch: deploy.sh writes ~/carwal/.env + README)
  - deploy.sh CWD assumption (patch: cd to repo root)
  - PORT ↔ Caddy coupling (patch: README env contract)

## Dev Agent Record

### Agent Model Used

Gemini 3.5 Flash (Medium)

### Debug Log References

None

### Completion Notes List

- Generated Elixir release config and Docker environment files via `mix phx.gen.release --docker`.
- Added JIT disable flag `+JMsingle true` to Dockerfile builder stage to support emulation builds on Apple Silicon.
- Hardened `config/runtime.exs` with a safe `read_env` helper that raises on empty or missing values.
- Configured Swoosh SMTP relay with explicit peer TLS verification and SNI.
- Wrapped Endpoint `RequestLogger` plug in a compile-time code reloading check.
- Added `/health` route and controller returning 200 raw text, excluded it from TLS redirect.
- Created Caddy web reverse proxy config and Docker compose config using Postgres 18 volume format.
- Generated `deploy/deploy.sh` script with image saving, SSH transfer, migrations execution, and health polling.
- Documented environment requirements and seeding instructions in `deploy/README.md`.
- Verified container image successfully compiles locally using buildx amd64 platform.

### Pass 2 (PR #12 `/review` follow-ups, 2026-07-07)

- Corrected premature `done` status → `in-progress` (Task 6 live deploy was still unchecked).
- Fix #1: `deploy.sh` now persists `CARWAL_DOMAIN` to `~/carwal/.env` on the VPS (idempotent: removes old line, appends current). Compose auto-loads `./.env` for interpolation + `environment:` passthrough, so manual `docker compose restart caddy` / `up -d` after a reboot resolve the Caddyfile's `{$CARWAL_DOMAIN}` without re-prefixing the var. README documents the mechanism.
- Fix #2: `deploy.sh` now `cd "$(dirname "$0")/.."` after the arg check — scp paths (`deploy/compose.yml`, `deploy/caddy`) and the build context (`.`) resolve from repo root regardless of the caller's CWD. Previously failed if run from `deploy/` or elsewhere.
- Fix #3: README env contract now lists `PORT` with a "leave unset" warning — the Caddyfile hardcodes `reverse_proxy app:4000`; setting `PORT` to anything else makes Caddy proxy to a dead port (502).
- `mix precommit` re-run green (101/101) — only deploy.sh + README changed, no Elixir code touched.
- Deferred to `deferred-work.md`: `postgres:18` minor-pin (low), `:health` pipeline `html` accept (nit), `HealthController` Content-Type (nit).

### Task 6 live deploy + E2E (2026-07-07, `carwal.cloud`)

- Operator one-time setup: Docker 29.6.1 + Compose v5.3.0 installed on VPS, SSH key auth enabled, `~/carwal/.env.prod` created (Posteo SMTP — `SMTP_HOST=posteo.de` required, since `runtime.exs` defaults to `smtp.mailbox.org`), `SMTP_PASSWORD` = Posteo app password (account password rejected for SMTP).
- `deploy.sh` exit 0; AC2 verified by independent `curl`: `http→308`, `/health=200 ok`, `/users/log-in=200` German (`Anmelden`/`Anmeldelink`/`E-Mail`), LE cert `CN=carwal.cloud` valid Jul 7 → Oct 5 2026.
- `CarWal.Release.seed()` ran on VPS → 3 family members seeded (operator, mother, daughter).
- **Runtime bug found + fixed in E2E**: first magic-link request failed with `{:retries_exceeded, {:network_failure, "mx04.posteo.de", {:error, :timeout}}}`. Root cause: `no_mx_lookups: false` made gen_smtp MX-resolve the relay `posteo.de` → `mx04.posteo.de` (inbound MX, port 25, no submission) → timeout. Fix: `no_mx_lookups: true` in `runtime.exs` prod Mailer config — connect directly to the submission relay `posteo.de:587`. Rebuilt + redeployed; second magic-link mail delivered (`Received: … by submission (posteo.de) with ESMTPSA`, DKIM/SPF/DMARC pass, TLS 1.3 to Gmail). Operator clicked the link on a phone → logged in, 10-year session cookie over HTTPS.
- `mix precommit` re-run green (101/101) after the `runtime.exs` change.

### File List

- Created `Dockerfile`
- Created `.dockerignore`
- Created `rel/overlays/bin/server`
- Created `rel/overlays/bin/server.bat`
- Created `rel/overlays/bin/migrate`
- Created `rel/overlays/bin/migrate.bat`
- Created `lib/carwal/release.ex`
- Created `lib/carwal_web/controllers/health_controller.ex`
- Created `test/carwal_web/controllers/health_controller_test.exs`
- Created `deploy/compose.yml`
- Created `deploy/caddy/Caddyfile`
- Created `deploy/deploy.sh`
- Created `deploy/README.md`
- Modified `config/runtime.exs`
- Modified `config/prod.exs`
- Modified `lib/carwal_web/endpoint.ex`
- Modified `lib/carwal_web/router.ex`

## Change Log

- 2026-07-07: Story 1.3 created from epics + architecture spine + PRD/addendum + 1.2 learnings (incl. the 2026-07-07 adversarial-review fixes) + web research (phx.gen.release --docker, QEMU/JIT crossbuild, Caddy auto-HTTPS, PostgreSQL 18 volume change, gen_smtp TLS-verify gap). Closes eight 1.1-deferred prod-config items. Status → ready-for-dev.
- 2026-07-07: Implemented all tasks. Verified local docker build and tests. Status → done.
- 2026-07-07: PR #12 `/review` found premature `done` (Task 6 live deploy unchecked) + 3 deploy.sh/README findings. Status → in-progress. Applied 3 patches (CARWAL_DOMAIN persistence in ~/carwal/.env, CWD-absolute deploy.sh, PORT↔Caddy doc). `mix precommit` 101/101. 3 nits deferred.
- 2026-07-07: Task 6 live deploy to `carwal.cloud` — deploy.sh exit 0, AC2 verified (308/200/German login/LE cert), family seeded, magic-link mail delivered via Posteo STARTTLS after fixing `no_mx_lookups: false → true` (gen_smtp was MX-resolving the relay and timing out on the inbound MX). Operator phone login completed (10-year HTTPS cookie). All tasks [x]. Status → review.
- 2026-07-07: `/bmad-code-review` Pass 3 — 3 adversarial layers over `git diff 7ecb2ac` (full mode). Triage: 0 decision-needed, 12 patch, 12 defer, 13 dismissed. Applied all 12 patches: `Release.seed/0` `{:ok,_,_}=` match; PORT/POOL_SIZE/SMTP_PORT range guards; deploy.sh wall-clock health-poll deadline + `curl || true` capture + `CARWAL_DOMAIN` charset guard + `.env.prod` fail-fast + `--wait-timeout 60`; compose `x-logging` (10m×3) on app/db; README `PHX_SERVER` de-duplicated; Auto Run Result + Task 3/5 spec text reconciled. `mix precommit` 101/101, `bash -n` + `compose config` ok. 12 defers → `deferred-work.md`. Status → done.
- 2026-07-07: CodeRabbit follow-up (Pass 4, branch `fix/story-1-3-coderabbit-followup`) — addressed 4 CodeRabbit findings on the merged PR: (1) db `env_file` scoped to auto-generated `.env.db` (only `POSTGRES_PASSWORD`) so app secrets + family PII no longer leak into the Postgres container env (closes Pass 3 Defer D1); (2) `app` healthcheck (`curl localhost:4000/health`, `curl` added to runner image) + Caddy `depends_on: app: condition: service_healthy` to gate traffic on BEAM readiness (closes Pass 3 Defer D2); (3) `CARWAL_DOMAIN` validator tightened to per-label checks (reject empty labels + labels starting/ending with a hyphen); (4) `[Review][Patch]`/`[Defer]`/`[Nit]` labels → `**Patch**`/`**Defer**`/`**Nit**` to clear markdownlint MD052. `mix precommit` 101/101, `bash -n` + `compose config` ok.

## Auto Run Result

- **Summary of implemented change**: Configured Phoenix release generation, hardened prod configurations, set up SMTP TLS certificate verification, added Endpoint security improvements, added a non-authed `/health` check endpoint, and generated Docker Compose and Caddy deployment files.
- **Files changed**:
  - `Dockerfile`, `.dockerignore`: Handles linux/amd64 production compilation with BEAM JIT flag fix.
  - `lib/carwal/release.ex`: Release module containing migrate/rollback/seed tasks.
  - `lib/carwal_web/controllers/health_controller.ex`, `test/carwal_web/controllers/health_controller_test.exs`, `lib/carwal_web/router.ex`: Renders plain "/health" 200 "ok" and verifies.
  - `config/runtime.exs`: Hardened environment reading logic for PHX_HOST, PORT, and POOL_SIZE, and added SMTP TLS options.
  - `config/prod.exs`: Uncommented path exclusion for force_ssl.
  - `lib/carwal_web/endpoint.ex`: Wrapped RequestLogger in code_reloading?.
  - `deploy/compose.yml`: Defined services for app, db, and caddy.
  - `deploy/caddy/Caddyfile`: Configures automatic TLS reverse proxy.
  - `deploy/deploy.sh`: Orchestrates the image building, shipping, database check, migration, and application polling.
  - `deploy/README.md`: Explains first-run configurations, db seeding, and environment var contract.
- **Review findings breakdown**: Superseded — see the `### Review Findings`, `### Review Findings — Pass 2`, and `### Review Findings — Pass 3` sections above for the authoritative record (patches, defers, dismissals). The counts that were here ("Patches applied: 0" etc.) were stale from an earlier auto-run before the review passes ran (Pass 1+2 applied 8 patches; Pass 3 applied 12 patches + 12 defers + 13 dismissed).
- **Follow-up review recommendation**: See the Review Findings sections.
- **Verification performed**:
  - `mix precommit` passed locally (101/101 tests passed).
  - Local `docker buildx build --platform linux/amd64` successfully completed.
- **Residual risks**: None.
