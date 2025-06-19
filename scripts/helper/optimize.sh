#!/bin/bash

# Nextcloud Post-Installation Optimization Script
# This script optimizes your Nextcloud installation for maximum performance
# Run this after your Nextcloud instance is up and running

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root!"
   exit 1
fi

# Container name
CONTAINER="nextcloud_app"

# Check if container is running
if ! docker ps | grep -q "$CONTAINER"; then
    print_error "Nextcloud container is not running!"
    exit 1
fi

print_info "Starting Nextcloud optimization..."

# Function to run occ commands
occ() {
    docker exec -u www-data "$CONTAINER" php occ "$@"
}

# 1. Enable maintenance mode during optimization
print_info "Enabling maintenance mode..."
occ maintenance:mode --on

# 2. Configure memory and execution limits
print_info "Configuring PHP memory limits..."
occ config:system:set memory_limit --value 4G
occ config:system:set max_execution_time --value 3600
occ config:system:set max_input_time --value 3600

# 3. Configure caching
print_info "Configuring caching..."
occ config:system:set memcache.local --value '\OC\Memcache\APCu'
occ config:system:set memcache.distributed --value '\OC\Memcache\Redis'
occ config:system:set memcache.locking --value '\OC\Memcache\Redis'
occ config:system:set redis host --value redis
occ config:system:set redis port --value 6379
occ config:system:set redis password --value "${REDIS_PASSWORD:-}"

# 4. Configure background jobs
print_info "Configuring background jobs..."
occ config:system:set backgroundjobs_mode --value cron

# 5. Enable and configure recommended apps
print_info "Enabling recommended apps..."
APPS=(
    "files_external"
    "richdocuments"
    "preview_generator"
    "fulltextsearch"
    "fulltextsearch_elasticsearch"
    "serverinfo"
    "extract"
    "text"
    "photos"
    "deck"
    "calendar"
    "contacts"
    "mail"
    "notes"
    "tasks"
)

for app in "${APPS[@]}"; do
    if occ app:list | grep -q "$app"; then
        occ app:enable "$app" || print_error "Failed to enable $app"
        print_success "Enabled $app"
    else
        print_info "App $app not available"
    fi
done

# 6. Configure preview generation
print_info "Configuring preview generation..."
occ config:app:set preview max_x --value 2048
occ config:app:set preview max_y --value 2048
occ config:system:set preview_max_x --value 2048
occ config:system:set preview_max_y --value 2048
occ config:system:set preview_max_memory --value 4096
occ config:system:set preview_max_filesize_image --value 50

# Configure preview providers
occ config:system:set enabledPreviewProviders 0 --value "OC\Preview\PNG"
occ config:system:set enabledPreviewProviders 1 --value "OC\Preview\JPEG"
occ config:system:set enabledPreviewProviders 2 --value "OC\Preview\GIF"
occ config:system:set enabledPreviewProviders 3 --value "OC\Preview\BMP"
occ config:system:set enabledPreviewProviders 4 --value "OC\Preview\XBitmap"
occ config:system:set enabledPreviewProviders 5 --value "OC\Preview\HEIC"
occ config:system:set enabledPreviewProviders 6 --value "OC\Preview\MarkDown"
occ config:system:set enabledPreviewProviders 7 --value "OC\Preview\MP3"
occ config:system:set enabledPreviewProviders 8 --value "OC\Preview\TXT"
occ config:system:set enabledPreviewProviders 9 --value "OC\Preview\Movie"
occ config:system:set enabledPreviewProviders 10 --value "OC\Preview\Photoshop"
occ config:system:set enabledPreviewProviders 11 --value "OC\Preview\TIFF"
occ config:system:set enabledPreviewProviders 12 --value "OC\Preview\SVG"
occ config:system:set enabledPreviewProviders 13 --value "OC\Preview\Font"

# Configure Imaginary if available
if docker ps | grep -q "imaginary"; then
    print_info "Configuring Imaginary for preview generation..."
    occ config:system:set preview_imaginary_url --value "http://imaginary:8088"
    print_success "Imaginary configured"
fi

# 7. Configure file handling
print_info "Configuring file handling..."
occ config:system:set files_access_control_hide_download --value false --type boolean
occ config:system:set default_quota --value "100 GB"
occ config:system:set quota_include_external_storage --value false --type boolean

# 8. Security hardening
print_info "Applying security hardening..."
occ config:system:set auth.bruteforce.protection.enabled --value true --type boolean
occ config:system:set auth.bruteforce.protection.testing --value false --type boolean
occ config:system:set files_antivirus_logging --value true --type boolean
occ config:system:set log_rotate_size --value 104857600 --type integer
occ config:system:set log.condition apps 0 --value admin_audit
occ config:system:set lost_password_link --value disabled
occ config:system:set token_auth_enforced --value true --type boolean

# 9. Configure Elasticsearch if available
if docker ps | grep -q "elasticsearch"; then
    print_info "Configuring Elasticsearch..."
    occ fulltextsearch:configure '{"search_platform":"OCA\\FullTextSearch_Elasticsearch\\Platform\\ElasticSearchPlatform"}' || true
    occ fulltextsearch_elasticsearch:configure '{"elastic_host":"http://elasticsearch:9200"}' || true
    print_success "Elasticsearch configured"
fi

# 10. Configure Collabora if available
if docker ps | grep -q "collabora"; then
    print_info "Configuring Collabora Online..."
    occ app:enable richdocuments || true
    occ config:app:set richdocuments wopi_url --value "https://collabora.${PRIMARY_DOMAIN:-localhost}"
    occ config:app:set richdocuments public_wopi_url --value "https://collabora.${PRIMARY_DOMAIN:-localhost}"
    occ config:app:set richdocuments disable_certificate_verification --value yes
    print_success "Collabora configured"
fi

# 11. Database optimization
print_info "Optimizing database indices..."
occ db:add-missing-indices
occ db:add-missing-columns
occ db:add-missing-primary-keys
occ db:convert-filecache-bigint --no-interaction

# 12. Configure default apps
print_info "Configuring default apps..."
occ config:system:set defaultapp --value files
occ config:system:set appstoreenabled --value true --type boolean

# 13. Configure logging
print_info "Configuring logging..."
occ config:system:set log_type --value file
occ config:system:set logfile --value "/var/www/html/data/nextcloud.log"
occ config:system:set loglevel --value 2
occ config:system:set logdateformat --value "Y-m-d H:i:s"

# 14. Configure theming
print_info "Configuring theming..."
occ config:app:set theming name --value "StepheyBot Cloud"
occ config:app:set theming slogan --value "Your Personal High-Performance Cloud"
occ config:app:set theming color --value "#FF1493"  # Neon pink

# 15. Run maintenance tasks
print_info "Running maintenance tasks..."
occ files:scan-app-data
occ maintenance:repair --include-expensive
occ maintenance:update:htaccess

# 16. Generate initial previews (background job)
if occ app:list | grep -q "preview_generator"; then
    print_info "Scheduling preview generation..."
    occ preview:generate-all -vvv &
    print_success "Preview generation scheduled in background"
fi

# 17. Configure LDAP/AD if needed
# Uncomment and configure if you use LDAP
# print_info "Configuring LDAP..."
# occ app:enable user_ldap
# occ ldap:create-empty-config
# occ ldap:set-config s01 ldapHost "ldap://your-ldap-server"
# occ ldap:set-config s01 ldapBase "dc=example,dc=com"

# 18. Final cleanup
print_info "Running final cleanup..."
occ files:cleanup
occ trashbin:cleanup --all-users
occ versions:cleanup

# 19. Disable maintenance mode
print_info "Disabling maintenance mode..."
occ maintenance:mode --off

# 20. Display summary
echo ""
print_success "Nextcloud optimization complete!"
echo ""
print_info "Summary of optimizations:"
echo "  • Memory limit: 4GB"
echo "  • Caching: APCu (local) + Redis (distributed/locking)"
echo "  • Background jobs: Cron mode"
echo "  • Preview generation: Configured with Imaginary support"
echo "  • Database: Optimized indices and structure"
echo "  • Security: Hardening applied"
echo ""
print_info "Next steps:"
echo "  1. Ensure cron job is configured for www-data user"
echo "  2. Monitor logs at: /var/www/html/data/nextcloud.log"
echo "  3. Access your instance at: https://${PRIMARY_DOMAIN:-your-domain.com}"
echo ""
print_info "For Collabora/Office support, install the 'Nextcloud Office' app from the app store"
echo ""

# Show current configuration
print_info "Current system configuration:"
occ config:list system --private=false

exit 0
