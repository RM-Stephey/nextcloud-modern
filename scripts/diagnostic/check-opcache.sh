#!/bin/bash

# OPcache Status Check Script
# This script monitors PHP OPcache usage in your Nextcloud container

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CONTAINER="nextcloud_app"

echo -e "${BLUE}=== PHP OPcache Status ===${NC}"
echo ""

# Create temporary PHP script to get OPcache status
docker exec $CONTAINER bash -c 'cat > /tmp/opcache-check.php << "EOF"
<?php
$status = opcache_get_status();
$config = opcache_get_configuration();

if (!$status) {
    echo "ERROR: OPcache is not enabled or not working properly\n";
    exit(1);
}

// Memory usage
$memory_used = $status["memory_usage"]["used_memory"];
$memory_free = $status["memory_usage"]["free_memory"];
$memory_wasted = $status["memory_usage"]["wasted_memory"];
$memory_total = $memory_used + $memory_free + $memory_wasted;

$memory_used_mb = round($memory_used / 1024 / 1024, 2);
$memory_free_mb = round($memory_free / 1024 / 1024, 2);
$memory_wasted_mb = round($memory_wasted / 1024 / 1024, 2);
$memory_total_mb = round($memory_total / 1024 / 1024, 2);
$memory_usage_percent = round(($memory_used / $memory_total) * 100, 2);

// Cache statistics
$num_cached_scripts = $status["opcache_statistics"]["num_cached_scripts"];
$max_cached_scripts = $status["opcache_statistics"]["max_cached_keys"];
$cache_hits = $status["opcache_statistics"]["hits"];
$cache_misses = $status["opcache_statistics"]["misses"];
$hit_rate = $cache_hits + $cache_misses > 0 ? round(($cache_hits / ($cache_hits + $cache_misses)) * 100, 2) : 0;

// Configuration
$memory_consumption = $config["directives"]["opcache.memory_consumption"] / 1024 / 1024;
$interned_strings_buffer = $config["directives"]["opcache.interned_strings_buffer"];
$max_accelerated_files = $config["directives"]["opcache.max_accelerated_files"];

// Output results
echo "MEMORY_USAGE|{$memory_usage_percent}|{$memory_used_mb}|{$memory_free_mb}|{$memory_wasted_mb}|{$memory_total_mb}\n";
echo "CACHE_STATS|{$num_cached_scripts}|{$max_cached_scripts}|{$hit_rate}|{$cache_hits}|{$cache_misses}\n";
echo "CONFIG|{$memory_consumption}|{$interned_strings_buffer}|{$max_accelerated_files}\n";
echo "ENABLED|" . ($status["opcache_enabled"] ? "1" : "0") . "\n";
echo "RESTART_PENDING|" . ($status["restart_pending"] ? "1" : "0") . "\n";
echo "RESTART_IN_PROGRESS|" . ($status["restart_in_progress"] ? "1" : "0") . "\n";
EOF'

# Run the PHP script and capture output
OUTPUT=$(docker exec $CONTAINER php /tmp/opcache-check.php 2>&1)

# Clean up
docker exec $CONTAINER rm -f /tmp/opcache-check.php

# Check if OPcache is working
if [[ $OUTPUT == ERROR* ]]; then
    echo -e "${RED}$OUTPUT${NC}"
    exit 1
fi

# Parse output
while IFS= read -r line; do
    IFS='|' read -r key values <<< "$line"

    case $key in
        MEMORY_USAGE)
            IFS='|' read -r _ percent used free wasted total <<< "$line"
            echo -e "${YELLOW}Memory Usage:${NC}"
            echo -e "  Total Memory:     ${total}MB"
            echo -e "  Used Memory:      ${used}MB (${percent}%)"
            echo -e "  Free Memory:      ${free}MB"
            echo -e "  Wasted Memory:    ${wasted}MB"

            # Check if memory usage is critical
            if (( $(echo "$percent > 90" | bc -l) )); then
                echo -e "  ${RED}⚠️  WARNING: OPcache memory usage is above 90%!${NC}"
                echo -e "  ${RED}   Consider increasing opcache.memory_consumption${NC}"
            elif (( $(echo "$percent > 80" | bc -l) )); then
                echo -e "  ${YELLOW}⚠️  NOTICE: OPcache memory usage is above 80%${NC}"
            else
                echo -e "  ${GREEN}✓ Memory usage is healthy${NC}"
            fi
            echo ""
            ;;

        CACHE_STATS)
            IFS='|' read -r _ cached max_keys hit_rate hits misses <<< "$line"
            echo -e "${YELLOW}Cache Statistics:${NC}"
            echo -e "  Cached Scripts:   ${cached}/${max_keys}"
            echo -e "  Cache Hit Rate:   ${hit_rate}%"
            echo -e "  Cache Hits:       ${hits}"
            echo -e "  Cache Misses:     ${misses}"

            if (( $(echo "$hit_rate < 90" | bc -l) )); then
                echo -e "  ${YELLOW}⚠️  Cache hit rate is below 90%${NC}"
            else
                echo -e "  ${GREEN}✓ Cache hit rate is good${NC}"
            fi
            echo ""
            ;;

        CONFIG)
            IFS='|' read -r _ memory interned max_files <<< "$line"
            echo -e "${YELLOW}Configuration:${NC}"
            echo -e "  Memory Consumption:        ${memory}MB"
            echo -e "  Interned Strings Buffer:   ${interned}MB"
            echo -e "  Max Accelerated Files:     ${max_files}"
            echo ""
            ;;

        ENABLED)
            IFS='|' read -r _ enabled <<< "$line"
            if [[ $enabled == "1" ]]; then
                echo -e "${GREEN}✓ OPcache is ENABLED${NC}"
            else
                echo -e "${RED}✗ OPcache is DISABLED${NC}"
            fi
            ;;

        RESTART_PENDING)
            IFS='|' read -r _ pending <<< "$line"
            if [[ $pending == "1" ]]; then
                echo -e "${YELLOW}⚠️  OPcache restart is pending${NC}"
            fi
            ;;

        RESTART_IN_PROGRESS)
            IFS='|' read -r _ progress <<< "$line"
            if [[ $progress == "1" ]]; then
                echo -e "${YELLOW}⚠️  OPcache restart in progress${NC}"
            fi
            ;;
    esac
done <<< "$OUTPUT"

echo ""
echo -e "${BLUE}=== Recommendations ===${NC}"

# Extract percentage for recommendations
percent=$(echo "$OUTPUT" | grep "MEMORY_USAGE" | cut -d'|' -f2)
if (( $(echo "$percent > 80" | bc -l) )); then
    echo -e "${YELLOW}Current OPcache memory usage is ${percent}%${NC}"
    echo ""
    echo "To increase OPcache memory, edit php-opcache.ini and change:"
    echo "  opcache.memory_consumption=512"
    echo "to a higher value like:"
    echo "  opcache.memory_consumption=1024"
    echo ""
    echo "Then restart the containers:"
    echo "  docker-compose restart nextcloud cron preview_generator"
else
    echo -e "${GREEN}OPcache configuration looks good!${NC}"
fi

# Show how to monitor in real-time
echo ""
echo -e "${BLUE}To monitor OPcache in real-time:${NC}"
echo "  watch -n 5 ./check-opcache.sh"
