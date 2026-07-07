# Production Deployment Guide

This directory contains the production Docker Compose setup, Caddy reverse-proxy configuration, and the deployment script for shipping CarWal to the VPS over HTTPS.

## 📋 Environment Variable Contract (`.env.prod`)

Before running your first deployment, create a `.env.prod` file on the target VPS inside `~/carwal/` with permissions locked down (`chmod 600`). This file should **never** be checked into version control.

### Required variables (Application will raise at boot if missing or empty)

*   `DATABASE_URL`: Connection string pointing to the compose-internal database.
    *   *Format*: `ecto://carwal:POSTGRES_PASSWORD@db/carwal`
*   `SECRET_KEY_BASE`: Used to sign/encrypt cookies and other session secrets.
    *   *Generation*: Run `mix phx.gen.secret` locally to generate a secure secret.
*   `PHX_HOST`: The domain name the app is running on (e.g., `carwal.example.com`). This is required to construct magic-link URLs and validate origin headers.
*   `SMTP_USERNAME`: Username for the sovereign mailbox SMTP relay (e.g., mailbox.org or Posteo).
*   `SMTP_PASSWORD`: Password for the SMTP relay.
*   `POSTGRES_PASSWORD`: The superuser password for the PostgreSQL database container. Must match the password specified in `DATABASE_URL`.
*   `VAPID_PUBLIC_KEY`: The public key for VAPID Web Push notifications.
    *   *Generation*: Generate locally using `mix run -e 'IO.inspect(ExNudge.generate_vapid_keys())'`.
*   `VAPID_PRIVATE_KEY`: The private key for VAPID Web Push notifications.
    *   *Generation*: Generate locally alongside `VAPID_PUBLIC_KEY`.

### Optional/Configurable variables

*   `VAPID_SUBJECT`: Contact URI (usually a `mailto:`) included in the VAPID header. Defaults to `"mailto:" <> MAIL_FROM` (derived from SMTP_USERNAME/MAIL_FROM).
*   `SMTP_HOST`: The host of the sovereign SMTP relay. Defaults to `smtp.mailbox.org`.
*   `SMTP_PORT`: The port of the SMTP relay. Defaults to `587` (STARTTLS).
*   `MAIL_FROM`: The sender email address. Must be owned by the SMTP account. Defaults to the value of `SMTP_USERNAME`.
*   `PHX_SERVER`: Optional. The image CMD (`/app/bin/server`) and the `bin/server` overlay set `PHX_SERVER=true` automatically, so it does not need to be in `.env.prod`. Setting it explicitly is harmless but redundant.
*   `POOL_SIZE`: The database pool size. Defaults to `10`.
*   `PORT`: The port the Phoenix endpoint binds to. Defaults to `4000`. **Leave unset** — the Caddyfile hardcodes `reverse_proxy app:4000`; setting `PORT` to anything else makes Caddy proxy to a dead port (502).
*   `ECTO_IPV6`: Set to `true` or `1` if the database host requires IPv6 reachability. (Keep unset when using default Compose networking).

### `CARWAL_DOMAIN` on the VPS (`~/carwal/.env`)

`CARWAL_DOMAIN` is **not** part of `.env.prod`. It is consumed by Caddy (the Caddyfile's `{$CARWAL_DOMAIN}` is resolved from the caddy container env, which Compose passes through from the `docker compose` process env). `deploy.sh` writes it to `~/carwal/.env` on every run, and Compose auto-loads `./.env` in the project directory for both variable interpolation and `environment:` passthrough.

This means **any manual `docker compose` command** run from `~/carwal/` (e.g. `docker compose restart caddy`, `docker compose up -d` after a VPS reboot) also picks up `CARWAL_DOMAIN` from `~/carwal/.env` — no need to prefix it on the shell. Do not delete `~/carwal/.env`.

### `~/carwal/.env.db` (auto-generated, do not create by hand)

The `db` service must not load the full `.env.prod` — that would expose `SECRET_KEY_BASE`, `SMTP_PASSWORD`, and `FAMILY_*_EMAIL` (family PII) to the Postgres container env (visible via `docker inspect`). Instead `deploy.sh` extracts only `POSTGRES_PASSWORD` from `.env.prod` into `~/carwal/.env.db` (`chmod 600`) on every run, and `compose.yml` points the `db` service at `.env.db`. Operators only ever create `.env.prod`; `.env.db` is regenerated each deploy — do not create or edit it by hand.

### App healthcheck + Caddy readiness gate

The `app` container has a healthcheck (`curl -fsS http://localhost:4000/health` — `curl` is installed in the runner image). Caddy's `depends_on: app` uses `condition: service_healthy`, so Caddy does not receive traffic until Bandit is actually serving, closing the post-restart 502 window. Because the healthcheck needs `curl` in the image, a deploy (`deploy.sh`, which rebuilds + ships the image) is required after any runner-image change before the gate works on a reboot.

### Real Family Members (PII via Environment)

These variables must be populated with the actual names and email addresses of the family members:

*   `FAMILY_OPERATOR_NAME` / `FAMILY_OPERATOR_EMAIL`
*   `FAMILY_MOTHER_NAME` / `FAMILY_MOTHER_EMAIL`
*   `FAMILY_DAUGHTER_NAME` / `FAMILY_DAUGHTER_EMAIL`

> [!IMPORTANT]
> The seeding process (`seeds.exs`) will **refuse to seed placeholder or empty emails** if a real mail adapter (SMTP) is configured. You must set these variables to valid, real email addresses before running the seed task.

---

## 🚀 First-Run Deployment Steps

1.  **Prepare the VPS**:
    *   Ensure Docker and Docker Compose are installed on the VPS.
    *   Configure DNS (A/AAAA records) pointing to the VPS IP.
2.  **Create `.env.prod` on VPS**:
    *   SSH into your VPS: `ssh user@vps-ip`
    *   Create directory: `mkdir -p ~/carwal`
    *   Create `~/carwal/.env.prod`, paste the environment variables, and secure the file:
        ```bash
        chmod 600 ~/carwal/.env.prod
        ```
3.  **Run the first deployment**:
    *   From your local M1 Mac, run the deploy script with the appropriate environment variables:
        ```bash
        CARWAL_HOST=user@vps-ip CARWAL_DOMAIN=family.carwal.de ./deploy/deploy.sh
        ```
4.  **Seed the database**:
    *   Once the first migration runs successfully, seed the database with the family members using:
        ```bash
        ssh user@vps-ip "cd ~/carwal && docker compose run --rm app bin/carwal eval 'CarWal.Release.seed()'"
        ```

---

## 🔒 Security Architecture

*   **No Public App/DB Ports**: Only the `caddy` service publishes ports to the host (`80`, `443`, `443/udp`). The `app` and `db` services are reachable only through the internal Docker network.
*   **Encrypted Mail**: Mail delivery is routed through a European sovereign provider with certificate verification strictly enforced via Erlang SSL trust store configuration (`:public_key.cacerts_get()`).
*   **HSTS & Force SSL**: Endpoint forces SSL redirecting, protected against header spoofing by stripping incoming headers at Caddy proxy layer.

---

## 📝 First Deploy Record (2026-07-07, `carwal.cloud`)

Operator one-time setup performed on the VPS before `deploy.sh` could run (these are preconditions, not part of the script):

1. **Docker + Compose installed** on the VPS via `curl -fsSL https://get.docker.com | sh` (Docker 29.6.1, Compose v5.3.0).
2. **SSH key auth enabled** for `root` — `deploy.sh` uses non-interactive `ssh`/`scp`, so password auth alone would fail. Pubkey added to `~/.ssh/authorized_keys`.
3. **`~/carwal/.env.prod` created** (`chmod 600`) with the full env contract above. SMTP provider is **Posteo** (`posteo.de:587` STARTTLS), not mailbox.org — `SMTP_HOST=posteo.de` is required because `runtime.exs` defaults `SMTP_HOST` to `smtp.mailbox.org`. `MAIL_FROM` is the Posteo account address.
4. **DNS** `carwal.cloud` A/AAAA → VPS (verified pre-deploy).

`deploy.sh` run (`CARWAL_HOST=root@<vps> CARWAL_DOMAIN=carwal.cloud ./deploy/deploy.sh`) — exit 0:

- `docker buildx build --platform linux/amd64 --load` completed under QEMU on the M1 (minutes, expected).
- Image shipped via `docker save | ssh docker load`.
- `db` started + reached `Healthy` (compose healthcheck, `pg_isready`).
- `CarWal.Release.migrate()` ran in a throwaway `app` container (post-load, pre-restart).
- `app` + `caddy` started; Caddy obtained a Let's Encrypt cert for `carwal.cloud` automatically.
- Health poll: 2 retries with `000` (curl during cert-issuance + app boot), then `200`.

AC2 verification (independent `curl` from the M1):

| Check | Result |
| --- | --- |
| `curl -I http://carwal.cloud` | `308 Permanent Redirect` → `https://carwal.cloud/` (Caddy) |
| `https://carwal.cloud/health` | `200` body `ok` |
| `https://carwal.cloud/users/log-in` | `200`, German login page (`Anmelden`, `Anmeldelink`, `E-Mail`) |
| TLS cert | issuer `Let's Encrypt`, `CN=carwal.cloud`, valid Jul 7 → Oct 5 2026 |

First-run seed (after deploy, separate command, not in `deploy.sh`):

```bash
ssh root@<vps> "cd ~/carwal && docker compose run --rm app bin/carwal eval 'CarWal.Release.seed()'"
```

Seeded 3 family members (operator, mother, daughter). The `Failed open sctp dynamic library: libsctp.so.1` warning is harmless — SMTP uses TCP, not SCTP.

### Magic-link smoke test (operator step, not the loop)

With the family seeded, the first real magic-link mail leaves the box via Posteo STARTTLS (TLS peer verification from Task 3):

1. Open `https://carwal.cloud/users/log-in` on a phone.
2. Enter the operator's seeded email.
3. Check the operator inbox for the magic-link mail (sender = `MAIL_FROM` Posteo address).
4. Open the link → logged in, 10-year session cookie set over HTTPS for the first time.

Throttle: one live link per member per 15-min window (Story 1.2) — a second request inside the window does not re-send.

**Result (2026-07-07):** mail delivered. Headers confirmed the intended path: `Received: from customer (localhost [127.0.0.1]) by submission (posteo.de) with ESMTPSA` — gen_smtp connected to the `posteo.de:587` submission relay, authenticated (Posteo app password), STARTTLS; Posteo → Gmail over TLS 1.3; DKIM/SPF/DMARC pass. Operator clicked the link on a phone → logged in, 10-year session cookie set over HTTPS.

> **SMTP relay must use `no_mx_lookups: true`.** The first attempt failed with `{:retries_exceeded, {:network_failure, "mx04.posteo.de", {:error, :timeout}}}`: with `no_mx_lookups: false`, gen_smtp MX-resolved the relay `posteo.de` and connected to `mx04.posteo.de` (the inbound MX, port 25 — submission not accepted there) → timeout. `runtime.exs` sets `no_mx_lookups: true` so gen_smtp connects directly to the configured relay host on port 587. This applies to any sovereign submission relay (Posteo, mailbox.org), not just Posteo.
