#!/usr/bin/env bash
set -euo pipefail

if [ -z "${CARWAL_HOST:-}" ] || [ -z "${CARWAL_DOMAIN:-}" ]; then
  echo "Error: CARWAL_HOST and CARWAL_DOMAIN environment variables must be set."
  echo "Usage: CARWAL_HOST=user@vps-ip CARWAL_DOMAIN=family.carwal.de ./deploy/deploy.sh"
  exit 1
fi

# CARWAL_DOMAIN is interpolated into remote shell commands and written to the
# VPS .env; reject anything outside a DNS hostname charset to prevent shell
# injection and Caddyfile parse failures.
case "$CARWAL_DOMAIN" in
  *[!A-Za-z0-9.-]*)
    echo "Error: CARWAL_DOMAIN must be a DNS hostname ([A-Za-z0-9.-]+), got: $CARWAL_DOMAIN"
    exit 1
    ;;
esac

# Fail fast before the (slow, QEMU) local build: .env.prod must already exist
# on the VPS per the README first-run steps.
echo "Verifying .env.prod exists on the VPS..."
ssh "$CARWAL_HOST" "test -f ~/carwal/.env.prod" || {
  echo "Error: ~/carwal/.env.prod not found on the VPS."
  echo "Create it first (see deploy/README.md), then re-run. Aborting before the local build."
  exit 1
}

# Resolve repo root so scp paths and the build context work from any CWD.
cd "$(dirname "$0")/.."

echo "Building local image for linux/amd64..."
docker buildx build --platform linux/amd64 --load -t carwal:latest .

echo "Shipping image to $CARWAL_HOST..."
docker save carwal:latest | ssh "$CARWAL_HOST" docker load

echo "Creating deploy directory and copying configuration..."
ssh "$CARWAL_HOST" "mkdir -p ~/carwal"
# Persist CARWAL_DOMAIN on the VPS so manual `docker compose` commands
# (restart, up after reboot) resolve the Caddyfile's {$CARWAL_DOMAIN}.
# Compose auto-loads ~/carwal/.env for interpolation + env passthrough.
ssh "$CARWAL_HOST" "touch ~/carwal/.env && sed -i '/^CARWAL_DOMAIN=/d' ~/carwal/.env && echo 'CARWAL_DOMAIN=$CARWAL_DOMAIN' >> ~/carwal/.env"
scp deploy/compose.yml "$CARWAL_HOST":~/carwal/compose.yml
ssh "$CARWAL_HOST" "rm -rf ~/carwal/caddy"
scp -r deploy/caddy "$CARWAL_HOST":~/carwal/

echo "Starting database service and waiting for it to be healthy..."
ssh "$CARWAL_HOST" "cd ~/carwal && CARWAL_DOMAIN=$CARWAL_DOMAIN docker compose up -d --wait --wait-timeout 60 db"

echo "Running migrations..."
ssh "$CARWAL_HOST" "cd ~/carwal && CARWAL_DOMAIN=$CARWAL_DOMAIN docker compose run --rm app bin/carwal eval 'CarWal.Release.migrate()'"

echo "Starting application and caddy reverse proxy..."
ssh "$CARWAL_HOST" "cd ~/carwal && CARWAL_DOMAIN=$CARWAL_DOMAIN docker compose up -d"

echo "Polling health endpoint at https://$CARWAL_DOMAIN/health..."
timeout=120
interval=3
# Wall-clock deadline (counts curl --max-time + sleep, not sleep alone) so the
# "timed out after N seconds" message is accurate.
deadline=$(( $(date +%s) + timeout ))
while true; do
  # curl prints the HTTP code via -w even on connection failure (000); drop the
  # old `|| echo failed` which produced a garbled "000failed" string.
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://$CARWAL_DOMAIN/health" || true)
  if [ "$http_code" = "200" ]; then
    echo "Deployment successful! App health check passed."
    break
  fi
  echo "App is not healthy yet (HTTP status/code: $http_code). Waiting..."
  sleep $interval
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "Error: Health check timed out after $timeout seconds."
    exit 1
  fi
done
