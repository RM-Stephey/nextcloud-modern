#!/bin/bash
# OAuth Test Script for StepheyBot
# Tests OAuth configuration for Dashy and related services

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== StepheyBot OAuth Configuration Test ===${NC}"
echo -e "${YELLOW}Testing connectivity to key services...${NC}"

# Test 1: Check if Dashy is accessible
echo -e "\n${YELLOW}Test 1: Checking Dashy service on port 8082...${NC}"
if curl -s -I http://localhost:8082 | grep "200 OK" > /dev/null; then
    echo -e "${GREEN}✓ Dashy is accessible on port 8082${NC}"
else
    echo -e "${RED}✗ Cannot access Dashy on port 8082${NC}"
    echo "  Try: docker-compose restart dashy"
fi

# Test 2: Check if OAuth2 Proxy is accessible
echo -e "\n${YELLOW}Test 2: Checking OAuth2 Proxy service on port 4180...${NC}"
if curl -s -I http://localhost:4180/ping | grep "200 OK" > /dev/null; then
    echo -e "${GREEN}✓ OAuth2 Proxy is accessible on port 4180${NC}"
else
    echo -e "${RED}✗ Cannot access OAuth2 Proxy on port 4180${NC}"
    echo "  Try: docker-compose restart oauth2-proxy"
fi

# Test 3: Check Keycloak connectivity
echo -e "\n${YELLOW}Test 3: Checking Keycloak connectivity...${NC}"
KEYCLOAK_URL=$(docker exec oauth2-proxy env | grep OAUTH2_PROXY_OIDC_ISSUER_URL | cut -d= -f2)
if [ -z "$KEYCLOAK_URL" ]; then
    echo -e "${RED}✗ Could not determine Keycloak URL from oauth2-proxy container${NC}"
else
    echo -e "   Keycloak URL: ${BLUE}$KEYCLOAK_URL${NC}"
    if curl -s -I "$KEYCLOAK_URL/.well-known/openid-configuration" | grep "200 OK" > /dev/null; then
        echo -e "${GREEN}✓ Keycloak OIDC endpoint is accessible${NC}"
    else
        echo -e "${RED}✗ Cannot access Keycloak OIDC endpoint${NC}"
        echo "  Check your Keycloak configuration and connectivity"
    fi
fi

# Test 4: Verify OAuth2 Proxy configuration
echo -e "\n${YELLOW}Test 4: Verifying OAuth2 Proxy configuration...${NC}"
docker exec oauth2-proxy env | grep -E "OAUTH2_PROXY_(PROVIDER|CLIENT_ID|REDIRECT_URL|OIDC_ISSUER_URL|COOKIE_DOMAIN)" | while read -r line; do
    echo -e "   ${BLUE}$line${NC}"
done

# Test 5: Check Nginx configuration for dashboard.stepheybot.dev
echo -e "\n${YELLOW}Test 5: Checking external connectivity...${NC}"
echo -e "   To fully test the OAuth flow, you need to access your dashboard from a browser:"
echo -e "   ${BLUE}https://dashboard.stepheybot.dev${NC}"
echo -e "\n   You should be redirected to the Keycloak login page, and after login,"
echo -e "   you should be redirected back to your Dashy dashboard."

echo -e "\n${YELLOW}Suggested VPS Nginx configuration fixes if OAuth is not working:${NC}"
echo -e "1. Ensure auth_request module is enabled: ${BLUE}nginx -V | grep http_auth_request_module${NC}"
echo -e "2. Check Nginx error logs: ${BLUE}tail -f /var/log/nginx/error.log${NC}"
echo -e "3. Test direct OAuth proxy access: ${BLUE}curl -I http://m0th3r.munchkin-ray.ts.net:4180/ping${NC}"
echo -e "4. Make sure the auth_request directive is properly configured and the @auth_check location is defined"

echo -e "\n${BLUE}=== Test Complete ===${NC}"
