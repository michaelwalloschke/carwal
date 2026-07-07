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

### Optional/Configurable variables

*   `SMTP_HOST`: The host of the sovereign SMTP relay. Defaults to `smtp.mailbox.org`.
*   `SMTP_PORT`: The port of the SMTP relay. Defaults to `587` (STARTTLS).
*   `MAIL_FROM`: The sender email address. Must be owned by the SMTP account. Defaults to the value of `SMTP_USERNAME`.
*   `PHX_SERVER`: Set to `true` (or any non-empty value) to run the Phoenix web server. (Note: The `bin/server` script sets this automatically, but keeping it in `.env.prod` is a good practice).
*   `POOL_SIZE`: The database pool size. Defaults to `10`.
*   `ECTO_IPV6`: Set to `true` or `1` if the database host requires IPv6 reachability. (Keep unset when using default Compose networking).

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
