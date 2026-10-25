#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Application configuration
# ============================================================

APP_ROOT="/opt/deployment-demo"
RELEASES_DIR="$APP_ROOT/releases"
CURRENT_LINK="$APP_ROOT/current"

APP_NAME="deployment-automation-demo"
HEALTH_URL="http://127.0.0.1:3000/health"

RELEASE_ID="${1:?Usage: deploy.sh <release_id> <branch_name>}"
BRANCH_NAME="${2:?Usage: deploy.sh <release_id> <branch_name>}"

# Validate the Git commit SHA.
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
echo "Deploy user : $(whoami)"

# Ensure the application was uploaded.
if [[ ! -d "$RELEASE_DIR/app" ]]; then
    echo "ERROR: Application files were not uploaded."
    exit 1
fi

cd "$RELEASE_DIR/app"

# ============================================================
# Install dependencies
# ============================================================

echo ">>> Installing production dependencies..."
npm ci --omit=dev

# ============================================================
# Validate application
# ============================================================

echo ">>> Checking application syntax..."
npm run check

echo ">>> Checking PM2 availability..."
pm2 --version

# ============================================================
# Switch active release
# ============================================================

echo ">>> Switching active release..."
ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"

# ============================================================
# Start or reload application
# ============================================================

echo ">>> Reloading PM2 application..."

if ! pm2 startOrReload \
    "$CURRENT_LINK/app/ecosystem.config.cjs" \
    --update-env; then

    echo "ERROR: PM2 reload failed."

    if [[ -n "$PREVIOUS_TARGET" && -d "$PREVIOUS_TARGET" ]]; then
        echo ">>> Restoring previous release..."
        ln -sfn "$PREVIOUS_TARGET" "$CURRENT_LINK"

        pm2 startOrReload \
            "$CURRENT_LINK/app/ecosystem.config.cjs" \
            --update-env || true
    else
        echo "No previous release is available for rollback."
    fi

    exit 1
fi

# ============================================================
# Health check
# ============================================================

echo ">>> Checking application health..."

HEALTHY=false

for attempt in $(seq 1 15); do
    if curl --fail --silent "$HEALTH_URL"; then
        HEALTHY=true
        echo
        break
    fi

    echo "Health check attempt $attempt/15 failed."
    sleep 2
done

# ============================================================
# Rollback on health-check failure
# ============================================================

if [[ "$HEALTHY" != "true" ]]; then
    echo "ERROR: Health check failed."

    if [[ -n "$PREVIOUS_TARGET" && -d "$PREVIOUS_TARGET" ]]; then
        echo ">>> Rolling back to the previous release..."

        ln -sfn "$PREVIOUS_TARGET" "$CURRENT_LINK"

        pm2 startOrReload \
            "$CURRENT_LINK/app/ecosystem.config.cjs" \
            --update-env || true
    else
        echo "No previous release is available for rollback."
    fi

    exit 1
fi

# ============================================================
# Save PM2 process list
# ============================================================

echo ">>> Saving PM2 process list..."
pm2 save

echo "========================================"
echo "DEPLOYMENT COMPLETED SUCCESSFULLY"
echo "========================================"
echo "Branch  : $BRANCH_NAME"
echo "Release : $RELEASE_ID"
