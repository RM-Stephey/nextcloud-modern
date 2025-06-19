#!/bin/bash

# Nextcloud Docker Update Script
# Updates Nextcloud from version 29 to 30.0.12
# This script includes safety checks and backup procedures

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.yml"
CONTAINER_NAME="nextcloud_app"
BACKUP_DIR="./backups/update-$(date +%Y%m%d-%H%M%S)"
OLD_VERSION="29"
NEW_VERSION="30"

echo -e "${BLUE}🚀 Nextcloud Update Script${NC}"
echo -e "${BLUE}========================${NC}"
echo -e "Updating from Nextcloud ${OLD_VERSION} to ${NEW_VERSION}.0.12\n"

# Function to check if command was successful
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1 failed${NC}"
        exit 1
    fi
}

# Pre-flight checks
echo -e "${YELLOW}📋 Running pre-flight checks...${NC}"

# Check if docker-compose file exists
if [ ! -f "$COMPOSE_FILE" ]; then
    echo -e "${RED}Error: docker-compose.yml not found in current directory${NC}"
    exit 1
fi

# Check if containers are running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${RED}Error: Nextcloud container is not running${NC}"
    echo "Please start the containers first: docker-compose up -d"
    exit 1
fi

# Create backup directory
echo -e "\n${YELLOW}📁 Creating backup directory...${NC}"
mkdir -p "$BACKUP_DIR"
check_status "Backup directory created"

# Step 1: Enable maintenance mode
echo -e "\n${YELLOW}🔧 Enabling maintenance mode...${NC}"
docker exec -u www-data $CONTAINER_NAME php occ maintenance:mode --on
check_status "Maintenance mode enabled"

# Step 2: Backup database
echo -e "\n${YELLOW}💾 Backing up database...${NC}"
docker exec nextcloud_db pg_dump -U nextcloud nextcloud | gzip > "$BACKUP_DIR/database-backup.sql.gz"
check_status "Database backup completed"

# Step 3: Backup config
echo -e "\n${YELLOW}📄 Backing up configuration...${NC}"
docker cp ${CONTAINER_NAME}:/var/www/html/config "$BACKUP_DIR/config"
check_status "Configuration backup completed"

# Step 4: Backup docker-compose.yml
echo -e "\n${YELLOW}📋 Backing up docker-compose.yml...${NC}"
cp docker-compose.yml "$BACKUP_DIR/docker-compose.yml.backup"
check_status "docker-compose.yml backup completed"

# Step 5: Create restore script
echo -e "\n${YELLOW}📝 Creating restore script...${NC}"
cat > "$BACKUP_DIR/restore.sh" << 'EOF'
#!/bin/bash
# Restore script for Nextcloud rollback

echo "🔄 Starting Nextcloud restore..."

# Restore docker-compose.yml
cp docker-compose.yml.backup ../docker-compose.yml

# Go back to main directory
cd ..

# Stop containers
docker-compose down

# Start with old version
docker-compose up -d

# Wait for containers to be ready
sleep 30

# Restore database
echo "Restoring database..."
gunzip -c database-backup.sql.gz | docker exec -i nextcloud_db psql -U nextcloud nextcloud

# Restore config
echo "Restoring configuration..."
docker cp config nextcloud_app:/var/www/html/

# Fix permissions
docker exec nextcloud_app chown -R www-data:www-data /var/www/html/config

# Disable maintenance mode
docker exec -u www-data nextcloud_app php occ maintenance:mode --off

echo "✅ Restore completed!"
EOF
chmod +x "$BACKUP_DIR/restore.sh"
check_status "Restore script created"

# Step 6: Update docker-compose.yml
echo -e "\n${YELLOW}📝 Updating docker-compose.yml to Nextcloud ${NEW_VERSION}...${NC}"
sed -i.bak "s/nextcloud:${OLD_VERSION}-fpm/nextcloud:${NEW_VERSION}-fpm/g" docker-compose.yml
check_status "docker-compose.yml updated"

# Also update cron and preview generator images
sed -i "s/nextcloud:${OLD_VERSION}-fpm/nextcloud:${NEW_VERSION}-fpm/g" docker-compose.yml

# Step 7: Pull new images
echo -e "\n${YELLOW}🐳 Pulling new Docker images...${NC}"
docker-compose pull nextcloud cron preview_generator
check_status "New images pulled"

# Step 8: Stop containers
echo -e "\n${YELLOW}🛑 Stopping containers...${NC}"
docker-compose stop nextcloud cron preview_generator
check_status "Containers stopped"

# Step 9: Start containers with new version
echo -e "\n${YELLOW}🚀 Starting containers with new version...${NC}"
docker-compose up -d nextcloud cron preview_generator
check_status "Containers started"

# Wait for container to be ready
echo -e "\n${YELLOW}⏳ Waiting for container to be ready...${NC}"
sleep 30

# Step 10: Run Nextcloud upgrade
echo -e "\n${YELLOW}🔄 Running Nextcloud upgrade process...${NC}"
docker exec -u www-data $CONTAINER_NAME php occ upgrade
check_status "Nextcloud upgrade completed"

# Step 11: Run maintenance tasks
echo -e "\n${YELLOW}🔨 Running post-upgrade maintenance...${NC}"

# Add missing indices
echo "Adding missing database indices..."
docker exec -u www-data $CONTAINER_NAME php occ db:add-missing-indices

# Add missing columns
echo "Adding missing database columns..."
docker exec -u www-data $CONTAINER_NAME php occ db:add-missing-columns

# Add missing primary keys
echo "Adding missing primary keys..."
docker exec -u www-data $CONTAINER_NAME php occ db:add-missing-primary-keys

# Convert to bigint if needed
echo "Converting columns to bigint..."
docker exec -u www-data $CONTAINER_NAME php occ db:convert-filecache-bigint --no-interaction || true

# Update .htaccess
echo "Updating .htaccess..."
docker exec -u www-data $CONTAINER_NAME php occ maintenance:update:htaccess

# Step 12: Disable maintenance mode
echo -e "\n${YELLOW}🔓 Disabling maintenance mode...${NC}"
docker exec -u www-data $CONTAINER_NAME php occ maintenance:mode --off
check_status "Maintenance mode disabled"

# Step 13: Clear caches
echo -e "\n${YELLOW}🧹 Clearing caches...${NC}"
docker exec -u www-data $CONTAINER_NAME php occ cache:clear
check_status "Caches cleared"

# Step 14: Restart all containers
echo -e "\n${YELLOW}🔄 Restarting all containers...${NC}"
docker-compose restart
check_status "All containers restarted"

# Final status check
echo -e "\n${YELLOW}📊 Running final status check...${NC}"
docker exec -u www-data $CONTAINER_NAME php occ status

echo -e "\n${GREEN}✅ Update completed successfully!${NC}"
echo -e "\n${BLUE}Important information:${NC}"
echo -e "- Backup location: ${BACKUP_DIR}"
echo -e "- Restore script: ${BACKUP_DIR}/restore.sh"
echo -e "- Previous docker-compose.yml: ${BACKUP_DIR}/docker-compose.yml.backup"
echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "1. Visit https://cloud.stepheybot.dev and verify everything works"
echo -e "2. Check the admin overview page for any new warnings"
echo -e "3. Test file upload/download functionality"
echo -e "4. If any issues occur, run: cd ${BACKUP_DIR} && ./restore.sh"
echo -e "\n${BLUE}Recommended: Keep the backup for at least 1 week before deleting${NC}"
