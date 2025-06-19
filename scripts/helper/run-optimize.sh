#!/bin/bash

# Nextcloud Optimization Wrapper Script
# This script sets the required environment variables and runs optimize.sh

# Set required environment variables
export REDIS_PASSWORD=$(grep REDIS_PASSWORD .env | cut -d'=' -f2 | tr -d '"' | tr -d "'")
export PRIMARY_DOMAIN="cloud.stepheybot.dev"

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting Nextcloud optimization process...${NC}"
echo -e "${YELLOW}Domain: ${PRIMARY_DOMAIN}${NC}"
echo -e "${YELLOW}Redis Password: [HIDDEN]${NC}"

# Check if optimize.sh exists
if [ ! -f "./scripts/optimize.sh" ]; then
    echo -e "${RED}Error: optimize.sh not found in ./scripts/${NC}"
    exit 1
fi

# Make optimize.sh executable if it isn't already
chmod +x ./scripts/optimize.sh

# Run the optimization script
./scripts/optimize.sh

# Check exit status
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Optimization completed successfully!${NC}"
else
    echo -e "${RED}Optimization failed. Check the output above for errors.${NC}"
    exit 1
fi
