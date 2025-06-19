#!/bin/bash

# Fix Nextcloud Configuration Script
# This script applies the necessary configuration to fix proxy and security issues

echo "Fixing Nextcloud configuration..."

# Get the container name
CONTAINER_NAME="nextcloud_app"

# Function to run occ commands
run_occ() {
    docker exec -u www-data $CONTAINER_NAME php occ "$@"
}

echo "Setting trusted proxies..."
# Set trusted proxies including Tailscale network
run_occ config:system:set trusted_proxies 0 --value="10.0.0.0/8"
run_occ config:system:set trusted_proxies 1 --value="172.16.0.0/12"
run_occ config:system:set trusted_proxies 2 --value="192.168.0.0/16"
run_occ config:system:set trusted_proxies 3 --value="100.64.0.0/10"
run_occ config:system:set trusted_proxies 4 --value="fd7a:115c:a1e0::/48"
run_occ config:system:set trusted_proxies 5 --value="173.245.48.0/20"
run_occ config:system:set trusted_proxies 6 --value="103.21.244.0/22"
run_occ config:system:set trusted_proxies 7 --value="103.22.200.0/22"
run_occ config:system:set trusted_proxies 8 --value="103.31.4.0/22"
run_occ config:system:set trusted_proxies 9 --value="141.101.64.0/18"
run_occ config:system:set trusted_proxies 10 --value="108.162.192.0/18"
run_occ config:system:set trusted_proxies 11 --value="190.93.240.0/20"
run_occ config:system:set trusted_proxies 12 --value="188.114.96.0/20"
run_occ config:system:set trusted_proxies 13 --value="197.234.240.0/22"
run_occ config:system:set trusted_proxies 14 --value="198.41.128.0/17"
run_occ config:system:set trusted_proxies 15 --value="162.158.0.0/15"
run_occ config:system:set trusted_proxies 16 --value="104.16.0.0/13"
run_occ config:system:set trusted_proxies 17 --value="104.24.0.0/14"
run_occ config:system:set trusted_proxies 18 --value="172.64.0.0/13"
run_occ config:system:set trusted_proxies 19 --value="131.0.72.0/22"

echo "Setting overwrite parameters..."
# Set overwrite parameters for proper URL handling
run_occ config:system:set overwritehost --value="cloud.stepheybot.dev"
run_occ config:system:set overwriteprotocol --value="https"
run_occ config:system:set overwritewebroot --value="/"
run_occ config:system:set overwrite.cli.url --value="https://cloud.stepheybot.dev"

echo "Setting trusted domains..."
# Set trusted domains
run_occ config:system:set trusted_domains 0 --value="cloud.stepheybot.dev"
run_occ config:system:set trusted_domains 1 --value="www.cloud.stepheybot.dev"
run_occ config:system:set trusted_domains 2 --value="m0th3r.munchkin-ray.ts.net"
run_occ config:system:set trusted_domains 3 --value="localhost"

echo "Configuring forwarded headers..."
# Configure forwarded for headers
run_occ config:system:set forwarded_for_headers 0 --value="HTTP_X_FORWARDED_FOR"

echo "Setting default phone region..."
# Set default phone region (adjust as needed)
run_occ config:system:set default_phone_region --value="US"

echo "Enabling maintenance mode temporarily..."
# Enable maintenance mode
run_occ maintenance:mode --on

echo "Clearing caches..."
# Clear various caches
run_occ cache:clear
run_occ config:cache:clear

echo "Running database optimizations..."
# Add missing indices and columns
run_occ db:add-missing-indices
run_occ db:add-missing-columns

echo "Converting database columns to big int (this may take a while)..."
# Convert to bigint for better performance
run_occ db:convert-filecache-bigint --no-interaction

echo "Disabling maintenance mode..."
# Disable maintenance mode
run_occ maintenance:mode --off

echo "Scanning files (this may take a while)..."
# Scan all files to ensure database is up to date
run_occ files:scan --all

echo "Configuration complete!"
echo ""
echo "Please restart the Nextcloud containers:"
echo "  cd /path/to/nextcloud-modern"
echo "  docker-compose restart"
echo ""
echo "Then check the admin panel for any remaining warnings."
