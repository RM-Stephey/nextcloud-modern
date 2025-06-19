#!/bin/bash

# Apply Nextcloud Configuration Fix
# This script fixes the trusted_proxies configuration issue

echo "🔧 Applying Nextcloud configuration fixes..."

# Container name
CONTAINER="nextcloud_app"

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "❌ Error: Container ${CONTAINER} is not running"
    echo "Please start the containers first: docker-compose up -d"
    exit 1
fi

echo "📋 Copying configuration script to container..."
docker cp fix-trusted-proxies.php ${CONTAINER}:/tmp/fix-trusted-proxies.php

echo "🔨 Running configuration fix..."
docker exec -u www-data ${CONTAINER} php /tmp/fix-trusted-proxies.php

echo "🧹 Clearing Nextcloud caches..."
docker exec -u www-data ${CONTAINER} php occ cache:clear
docker exec -u www-data ${CONTAINER} php occ config:cache:clear

echo "📁 Cleaning up temporary files..."
docker exec ${CONTAINER} rm /tmp/fix-trusted-proxies.php

echo "🔄 Restarting Nextcloud container..."
docker-compose restart nextcloud web

echo ""
echo "✅ Configuration fix applied!"
echo ""
echo "Please wait a moment for the containers to restart, then:"
echo "1. Visit https://cloud.stepheybot.dev/settings/admin/overview"
echo "2. Check if the warnings have been resolved"
echo ""
echo "If you still see warnings about .well-known URLs, you may need to:"
echo "1. Update your edge nginx configuration"
echo "2. Clear your browser cache"
echo "3. Check the logs: docker-compose logs -f nextcloud"
