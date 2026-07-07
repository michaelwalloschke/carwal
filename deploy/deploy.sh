#!/usr/bin/env bash
set -euo pipefail

if [ -z "${CARWAL_HOST:-}" ] || [ -z "${CARWAL_DOMAIN:-}" ]; then
  echo "Error: CARWAL_HOST and CARWAL_DOMAIN environment variables must be set."
  echo "Usage: CARWAL_HOST=user@vps-ip CARWAL_DOMAIN=family.carwal.de ./deploy/deploy.sh"
  exit 1
fi

echo "Building local image for linux/amd64..."
docker buildx build --platform linux/amd64 --load -t carwal:latest .

echo "Shipping image to $CARWAL_HOST..."
docker save carwal:latest | ssh "$CARWAL_HOST" docker load

echo "Creating deploy directory and copying configuration..."
ssh "$CARWAL_HOST" "mkdir -p ~/carwal"
scp deploy/compose.yml "$CARWAL_HOST":~/carwal/compose.yml
ssh "$CARWAL_HOST" "rm -rf ~/carwal/caddy"
scp -r deploy/caddy "$CARWAL_HOST":~/carwal/

echo "Starting database service and waiting for it to be healthy..."
ssh "$CARWAL_HOST" "cd ~/carwal && CARWAL_DOMAIN=$CARWAL_DOMAIN docker compose up -d --wait db"

echo "Running migrations..."
ssh "$CARWAL_HOST" "cd ~/carwal && CARWAL_DOMAIN=$CARWAL_DOMAIN docker compose run --rm app bin/carwal eval 'CarWal.Release.migrate()'"

echo "Starting application and caddy reverse proxy..."
ssh "$CARWAL_HOST" "cd ~/carwal && CARWAL_DOMAIN=$CARWAL_DOMAIN docker compose up -d"

echo "Polling health endpoint at https://$CARWAL_DOMAIN/health..."
timeout=120
elapsed=0
interval=3
while true; do
  # Perform curl with a timeout and fallback in case of DNS or connection issues
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://$CARWAL_DOMAIN/health" || echo "failed")
  if [ "$http_code" = "200" ]; then
    echo "Deployment successful! App health check passed."
    break
  fi
  echo "App is not healthy yet (HTTP status/code: $http_code). Waiting..."
  sleep $interval
  elapsed=$((elapsed + interval))
  if [ $elapsed -ge $timeout ]; then
    echo "Error: Health check timed out after $timeout seconds."
    exit 1
  fi
done
