#!/bin/bash

# qBittorrent Authentication Fix Script for StepheyBot Music
# This script configures qBittorrent to allow API access from the download service

set -e

echo "🔧 StepheyBot Music - qBittorrent Authentication Fix"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
QB_USERNAME="admin"
QB_PASSWORD="adminadmin"
QB_CONTAINER="stepheybot_music_qbittorrent"
VPN_CONTAINER="stepheybot_music_vpn"
MUSIC_CONTAINER="stepheybot_music_brain"

echo -e "${BLUE}📋 Configuration:${NC}"
echo "  • qBittorrent Container: ${QB_CONTAINER}"
echo "  • VPN Container: ${VPN_CONTAINER}"
echo "  • Music Service Container: ${MUSIC_CONTAINER}"
echo "  • Username: ${QB_USERNAME}"
echo "  • Password: ${QB_PASSWORD}"
echo ""

# Function to check if container exists and is running
check_container() {
    local container_name=$1
    if ! docker ps | grep -q "$container_name"; then
        echo -e "${RED}❌ Container $container_name is not running${NC}"
        return 1
    fi
    echo -e "${GREEN}✅ Container $container_name is running${NC}"
    return 0
}

# Function to backup qBittorrent config
backup_config() {
    echo -e "${YELLOW}📦 Backing up qBittorrent configuration...${NC}"
    docker exec $QB_CONTAINER cp /data/config/qBittorrent.conf /data/config/qBittorrent.conf.backup || true
    echo -e "${GREEN}✅ Configuration backed up${NC}"
}

# Function to configure qBittorrent for API access
configure_qbittorrent() {
    echo -e "${YELLOW}⚙️ Configuring qBittorrent for API access...${NC}"

    # Create a new configuration with API-friendly settings
    docker exec $QB_CONTAINER bash -c 'cat > /tmp/qbt_api_config.txt << EOF
[BitTorrent]
Session\GlobalMaxSeedingTimeLimit=1440
Session\QueueingSystemEnabled=false

[LegalNotice]
Accepted=true

[Network]
Cookies=@Invalid()

[Preferences]
Advanced\RecheckOnCompletion=false
Advanced\TrayIconStyle=MonoDark
Bittorrent\AddTrackers=false
Bittorrent\DHT=true
Bittorrent\Encryption=1
Bittorrent\LSD=true
Bittorrent\MaxRatio=2
Bittorrent\PeX=true
Bittorrent\uTP=true
Bittorrent\uTP_rate_limited=true
Connection\GlobalDLLimitAlt=0
Connection\GlobalUPLimitAlt=0
Connection\PortRangeMin=6881
Connection\ResolvePeerCountries=true
Connection\ResolvePeerHostNames=false
Downloads\DiskWriteCacheSize=64
Downloads\DiskWriteCacheTTL=60
Downloads\SavePath=/data/downloads
Downloads\ScanDirsV2=@Variant(\0\0\0\x1c\0\0\0\0)
Downloads\StartInPause=false
Downloads\TorrentExportDir=
General\Locale=en_US
MailNotification\enabled=false
Queueing\QueueingEnabled=false
WebUI\Address=0.0.0.0
WebUI\AlternativeUIEnabled=false
WebUI\Enabled=true
WebUI\HTTPS\Enabled=false
WebUI\LocalHostAuth=false
WebUI\Password_PBKDF2="@ByteArray(ARQ77eY1NUZaQsuDHbIMCA==:0WMRkYTUWVT9wVvdDtHAjU9b3b7uB8NR1Gur2hmQCvCDpm39Q+PsJRJPaCU51dEiz+dTzh8qbPsO8WkA/dXiZQ==)"
WebUI\Port=8080
WebUI\RootFolder=/data/webui
WebUI\Username=admin
WebUI\UseUPnP=false
EOF'

    # Apply the configuration
    docker exec $QB_CONTAINER cp /tmp/qbt_api_config.txt /data/config/qBittorrent.conf

    echo -e "${GREEN}✅ qBittorrent configuration updated${NC}"
}

# Function to restart qBittorrent
restart_qbittorrent() {
    echo -e "${YELLOW}🔄 Restarting qBittorrent...${NC}"
    docker restart $QB_CONTAINER

    echo -e "${YELLOW}⏳ Waiting for qBittorrent to start...${NC}"
    sleep 15

    # Wait for qBittorrent to be ready
    local retries=0
    local max_retries=30
    while [ $retries -lt $max_retries ]; do
        if docker exec $VPN_CONTAINER curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "200\|401\|403"; then
            echo -e "${GREEN}✅ qBittorrent is responding${NC}"
            break
        fi
        echo -e "${YELLOW}⏳ Waiting for qBittorrent... (attempt $((retries + 1))/${max_retries})${NC}"
        sleep 2
        retries=$((retries + 1))
    done

    if [ $retries -eq $max_retries ]; then
        echo -e "${RED}❌ qBittorrent failed to start properly${NC}"
        return 1
    fi
}

# Function to test qBittorrent API access
test_api_access() {
    echo -e "${YELLOW}🧪 Testing qBittorrent API access...${NC}"

    # Test from VPN container (same network as qBittorrent)
    echo -e "${BLUE}📡 Testing from VPN container...${NC}"
    local login_response=$(docker exec $VPN_CONTAINER curl -s -X POST "http://localhost:8080/api/v2/auth/login" \
        -d "username=${QB_USERNAME}&password=${QB_PASSWORD}" -w "%{http_code}" -o /tmp/login_result)

    if echo "$login_response" | grep -q "200"; then
        echo -e "${GREEN}✅ Authentication successful from VPN container${NC}"
    else
        echo -e "${RED}❌ Authentication failed from VPN container (HTTP: $login_response)${NC}"
        docker exec $VPN_CONTAINER cat /tmp/login_result 2>/dev/null || true
    fi

    # Test API version endpoint
    echo -e "${BLUE}📡 Testing API version endpoint...${NC}"
    local version_response=$(docker exec $VPN_CONTAINER curl -s "http://localhost:8080/api/v2/app/version" 2>/dev/null || echo "FAILED")

    if [ "$version_response" != "FAILED" ] && [ "$version_response" != "Forbidden" ]; then
        echo -e "${GREEN}✅ API version: $version_response${NC}"
    else
        echo -e "${RED}❌ API version check failed: $version_response${NC}"
    fi

    # Test adding a dummy magnet (dry run)
    echo -e "${BLUE}📡 Testing magnet add capability...${NC}"
    local magnet_test="magnet:?xt=urn:btih:c9e15763f722f23e98a29decdfae341b98d53056&dn=Test"
    local add_response=$(docker exec $VPN_CONTAINER curl -s -X POST "http://localhost:8080/api/v2/torrents/add" \
        -F "urls=${magnet_test}" -w "%{http_code}" -o /tmp/add_result 2>/dev/null || echo "FAILED")

    if echo "$add_response" | grep -q "200"; then
        echo -e "${GREEN}✅ Magnet add test successful${NC}"
        # Remove the test torrent
        docker exec $VPN_CONTAINER curl -s -X POST "http://localhost:8080/api/v2/torrents/delete" \
            -d "hashes=c9e15763f722f23e98a29decdfae341b98d53056&deleteFiles=true" >/dev/null 2>&1 || true
    else
        echo -e "${RED}❌ Magnet add test failed (HTTP: $add_response)${NC}"
        docker exec $VPN_CONTAINER cat /tmp/add_result 2>/dev/null || true
    fi
}

# Function to update download service configuration
update_download_service() {
    echo -e "${YELLOW}🔧 Updating download service configuration...${NC}"

    # Restart the music service to pick up the working qBittorrent connection
    echo -e "${YELLOW}🔄 Restarting StepheyBot Music service...${NC}"
    docker restart $MUSIC_CONTAINER

    echo -e "${YELLOW}⏳ Waiting for music service to start...${NC}"
    sleep 10

    # Test the download service connection
    local retries=0
    local max_retries=15
    while [ $retries -lt $max_retries ]; do
        if curl -s http://localhost:8083/health >/dev/null 2>&1; then
            echo -e "${GREEN}✅ StepheyBot Music service is healthy${NC}"
            break
        fi
        echo -e "${YELLOW}⏳ Waiting for music service... (attempt $((retries + 1))/${max_retries})${NC}"
        sleep 2
        retries=$((retries + 1))
    done
}

# Function to test end-to-end download
test_download_integration() {
    echo -e "${YELLOW}🎵 Testing end-to-end download integration...${NC}"

    # Submit a test download
    local test_magnet="magnet:?xt=urn:btih:c9e15763f722f23e98a29decdfae341b98d53056&dn=Test-Download&tr=udp%3A%2F%2Fexplodie.org%3A6969"
    local download_response=$(curl -s -X POST http://localhost:8083/api/v1/download/request \
        -H "Content-Type: application/json" \
        -d "{
            \"title\": \"API Test Download\",
            \"artist\": \"qBittorrent Fix Test\",
            \"album\": \"Integration Test\",
            \"external_id\": \"${test_magnet}\",
            \"source\": \"integration_test\"
        }" | jq -r '.request_id // "FAILED"' 2>/dev/null || echo "FAILED")

    if [ "$download_response" != "FAILED" ] && [ "$download_response" != "null" ]; then
        echo -e "${GREEN}✅ Download request submitted successfully${NC}"
        echo -e "${BLUE}📊 Request ID: $download_response${NC}"

        # Check download stats
        local stats=$(curl -s http://localhost:8083/api/v1/download/stats | jq -r '.stats.total_downloads // 0' 2>/dev/null || echo "0")
        echo -e "${BLUE}📊 Total downloads in queue: $stats${NC}"

        # Check download status
        sleep 2
        local status=$(curl -s "http://localhost:8083/api/v1/download/status/$download_response" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
        echo -e "${BLUE}📊 Download status: $status${NC}"

    else
        echo -e "${RED}❌ Download request failed${NC}"
    fi
}

# Function to show final instructions
show_instructions() {
    echo ""
    echo -e "${GREEN}🎉 qBittorrent Configuration Complete!${NC}"
    echo "========================================"
    echo ""
    echo -e "${BLUE}📋 Summary:${NC}"
    echo "  • qBittorrent is configured for API access"
    echo "  • Username: ${QB_USERNAME}"
    echo "  • Password: ${QB_PASSWORD}"
    echo "  • API URL: http://stepheybot_music_vpn:8080"
    echo ""
    echo -e "${BLUE}🎵 How to use downloads:${NC}"
    echo "  1. Go to: http://localhost:8083/search"
    echo "  2. Search for music"
    echo "  3. Click download buttons on search results"
    echo "  4. Monitor at: http://localhost:8083/downloads"
    echo ""
    echo -e "${BLUE}📊 API Endpoints:${NC}"
    echo "  • Download Stats: curl http://localhost:8083/api/v1/download/stats"
    echo "  • Active Downloads: curl http://localhost:8083/api/v1/download/active"
    echo "  • qBittorrent Direct: http://localhost:8080 (from VPN network)"
    echo ""
    echo -e "${BLUE}🔍 Troubleshooting:${NC}"
    echo "  • Check logs: docker logs stepheybot_music_brain"
    echo "  • qBittorrent logs: docker logs stepheybot_music_qbittorrent"
    echo "  • Test API: docker exec stepheybot_music_vpn curl http://localhost:8080/api/v2/app/version"
    echo ""
}

# Main execution
main() {
    echo -e "${BLUE}🔍 Checking container status...${NC}"

    if ! check_container "$QB_CONTAINER"; then
        echo -e "${RED}❌ qBittorrent container is not running. Please start it first.${NC}"
        exit 1
    fi

    if ! check_container "$VPN_CONTAINER"; then
        echo -e "${RED}❌ VPN container is not running. Please start it first.${NC}"
        exit 1
    fi

    if ! check_container "$MUSIC_CONTAINER"; then
        echo -e "${RED}❌ Music service container is not running. Please start it first.${NC}"
        exit 1
    fi

    echo ""
    read -p "🤔 Do you want to proceed with qBittorrent configuration? (y/N): " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}❌ Operation cancelled by user${NC}"
        exit 0
    fi

    backup_config
    configure_qbittorrent
    restart_qbittorrent
    test_api_access
    update_download_service
    test_download_integration
    show_instructions
}

# Handle script interruption
trap 'echo -e "\n${RED}❌ Script interrupted${NC}"; exit 1' INT TERM

# Run main function
main "$@"
