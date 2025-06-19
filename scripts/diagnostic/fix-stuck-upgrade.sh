#!/bin/bash

# Fix Stuck Nextcloud Upgrade Script
# This script resolves stuck upgrades and completes the update process

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONTAINER_NAME="nextcloud_app"
DB_CONTAINER="nextcloud_db"

echo -e "${BLUE}🔧 Nextcloud Stuck Upgrade Fix${NC}"
echo -e "${BLUE}==============================${NC}\n"

# Function to check if command was successful
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1 failed${NC}"
        return 1
    fi
}

# Function to run occ commands
run_occ() {
    docker exec -u www-data $CONTAINER_NAME php occ "$@"
}

# Step 1: Check current status
echo -e "${YELLOW}📊 Checking current status...${NC}"
docker exec -u www-data $CONTAINER_NAME php occ status || true

# Step 2: Check logs for errors
echo -e "\n${YELLOW}📋 Checking recent error logs...${NC}"
echo "Last 20 lines from Nextcloud log:"
docker exec $CONTAINER_NAME tail -20 /var/www/html/data/nextcloud.log 2>/dev/null || echo "Could not read log file"

# Step 3: Disable maintenance mode
echo -e "\n${YELLOW}🔓 Disabling maintenance mode...${NC}"
run_occ maintenance:mode --off || {
    echo -e "${YELLOW}Failed with occ, trying direct config edit...${NC}"

    # Try to disable maintenance mode by editing config directly
    docker exec $CONTAINER_NAME bash -c "
        cd /var/www/html
        if [ -f config/config.php ]; then
            cp config/config.php config/config.php.bak
            sed -i \"s/'maintenance' => true,/'maintenance' => false,/g\" config/config.php
            echo 'Maintenance mode disabled via config edit'
        fi
    "
}
check_status "Maintenance mode disabled"

# Step 4: Clear upgrade lock if exists
echo -e "\n${YELLOW}🔓 Clearing upgrade locks...${NC}"
docker exec $CONTAINER_NAME bash -c "
    cd /var/www/html/data
    if [ -f .ocdata ]; then
        # Remove upgrade lock files if they exist
        rm -f upgrade-*.lock 2>/dev/null || true
        rm -f updater-*.lock 2>/dev/null || true
        echo 'Upgrade locks cleared'
    fi
"
check_status "Locks cleared"

# Step 5: Check version mismatch
echo -e "\n${YELLOW}🔍 Checking for version mismatch...${NC}"
INSTALLED_VERSION=$(run_occ status --output=json | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
echo "Installed version: $INSTALLED_VERSION"

# Step 6: Re-run upgrade if needed
echo -e "\n${YELLOW}🚀 Attempting to complete upgrade...${NC}"
run_occ upgrade || {
    echo -e "${YELLOW}Standard upgrade failed, trying repair mode...${NC}"

    # Try repair
    run_occ maintenance:repair || true

    # Try upgrade again
    run_occ upgrade || {
        echo -e "${RED}Upgrade still failing. Checking database...${NC}"

        # Check if database migrations are stuck
        docker exec $DB_CONTAINER psql -U nextcloud -d nextcloud -c "
            SELECT * FROM oc_migrations
            WHERE app='core'
            ORDER BY version DESC
            LIMIT 5;
        " 2>/dev/null || echo "Could not check migrations table"
    }
}

# Step 7: Run post-upgrade maintenance
echo -e "\n${YELLOW}🔨 Running post-upgrade maintenance...${NC}"

# Add missing indices
echo "Adding missing database indices..."
run_occ db:add-missing-indices || echo "Warning: Could not add indices"

# Add missing columns
echo "Adding missing database columns..."
run_occ db:add-missing-columns || echo "Warning: Could not add columns"

# Add missing primary keys
echo "Adding missing primary keys..."
run_occ db:add-missing-primary-keys || echo "Warning: Could not add primary keys"

# Update .htaccess
echo "Updating .htaccess..."
run_occ maintenance:update:htaccess || echo "Warning: Could not update htaccess"

# Step 8: Clear all caches
echo -e "\n${YELLOW}🧹 Clearing all caches...${NC}"
run_occ cache:clear || echo "Warning: Could not clear cache"

# Try to clear file caches manually
docker exec $CONTAINER_NAME bash -c "
    rm -rf /var/www/html/data/appdata_*/js/core/* 2>/dev/null || true
    rm -rf /var/www/html/data/appdata_*/css/core/* 2>/dev/null || true
"

# Step 9: Re-enable apps if needed
echo -e "\n${YELLOW}📱 Checking app status...${NC}"
run_occ app:list | grep -E "Enabled|Disabled" || true

# Step 10: Final status check
echo -e "\n${YELLOW}📊 Final status check...${NC}"
run_occ status

# Step 11: Check for any remaining issues
echo -e "\n${YELLOW}🔍 Running system check...${NC}"
run_occ check || true

# Step 12: Restart containers
echo -e "\n${YELLOW}🔄 Restarting containers...${NC}"
docker-compose restart nextcloud web cron
check_status "Containers restarted"

echo -e "\n${GREEN}✅ Fix completed!${NC}"
echo -e "\n${BLUE}Next steps:${NC}"
echo -e "1. Visit https://cloud.stepheybot.dev"
echo -e "2. Check the admin overview page"
echo -e "3. If you see any errors, check: docker-compose logs -f nextcloud"
echo -e "\n${YELLOW}If the upgrade is still stuck:${NC}"
echo -e "1. Check if you need to manually update the version in config/config.php"
echo -e "2. The version should be '30.0.12.7'"
echo -e "3. You can edit it with:"
echo -e "   docker exec -it $CONTAINER_NAME bash"
echo -e "   nano /var/www/html/config/config.php"
