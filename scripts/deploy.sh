#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="/opt/deployment-demo"
RELEASES_DIR="$APP_ROOT/releases"
CURRENT_LINK="$APP_ROOT/current"

DEPLOY_USER="deployer"
APP_NAME="deployment-automation-demo"
HEALTH_URL="http://127.0.0.1:3000/health"

RELEASE_ID="${1:?Usage: deploy.sh <release_id> <branch_name>}"
BRANCH_NAME="${2:?Usage: deploy.sh <release_id> <branch_name>}"

# The release ID is a Git commit SHA, not an arbitrary filesystem path.
if [[ ! "$RELEASE_ID" =~ ^[0-9a-f]{40}$ ]]; then
  echo "ERROR: Invalid release ID."
  exit 1
fi

RELEASE_DIR="$RELEASES_DIR/$RELEASE_ID"
PREVIOUS_TARGET="$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)"

echo "========================================"
echo "      DEVELOPMENT DEPLOYMENT"
echo "========================================"
echo "Application : $APP_NAME"
echo "Branch      : $BRANCH_NAME"
echo "Release     : $RELEASE_ID"
echo "Release dir : $RELEASE_DIR"

if [[ ! -d "$RELEASE_DIR/app" ]]; then
  echo "ERROR: Application files were not uploaded."
  exit 1
fi

cd "$RELEASE_DIR/app"

echo ">>> Installing production dependencies..."
sudo -u "$DEPLOY_USER" -H npm ci --omit=dev

echo ">>> Checking application syntax..."
sudo -u "$DEPLOY_USER" -H npm run check

echo ">>> Checking PM2 availability..."
sudo -u "$DEPLOY_USER" -H pm2 --version

echo ">>> Switching active release..."
ln -sfn "$RELEASE_DIR" "$APP_ROOT/current"

echo ">>> Reloading PM2 application..."
if ! sudo -u "$DEPLOY_USER" -H pm2 startOrReload \
  "$CURRENT_LINK/app/ecosystem.config.cjs" \
  --update-env; then

  echo "ERROR: PM2 reload failed."

  if [[ -n "$PREVIOUS_TARGET" && -d "$PREVIOUS_TARGET" ]]; then
    ln -sfn "$PREVIOUS_TARGET" "$CURRENT_LINK"
    sudo -u "$DEPLOY_USER" -H pm2 startOrReload \
      "$CURRENT_LINK/app/ecosystem.config.cjs" \
      --update-env || true
  fi

  exit 1
fi

echo ">>> Checking application health..."

HEALTHY=false

for attempt in $(seq 1 15); do
  if curl --fail --silent --show-error "$HEALTH_URL"; then
    HEALTHY=true
    echo
    break
  fi

  echo "Health check attempt $attempt/15 failed."
  sleep 2
done

if [[ "$HEALTHY" != "true" ]]; then
  echo "ERROR: Health check failed."

  if [[ -n "$PREVIOUS_TARGET" && -d "$PREVIOUS_TARGET" ]]; then
    echo ">>> Rolling back to the previous release..."
    ln -sfn "$PREVIOUS_TARGET" "$CURRENT_LINK"

    sudo -u "$DEPLOY_USER" -H pm2 startOrReload \
      "$CURRENT_LINK/app/ecosystem.config.cjs" \
      --update-env || true
  else
    echo "No previous release is available for rollback."
  fi

  exit 1
fi

echo ">>> Saving PM2 process list..."
sudo -u "$DEPLOY_USER" -H pm2 save

echo ">>> Deployment completed successfully."
echo "Branch: $BRANCH_NAME"
echo "Release: $RELEASE_ID"
