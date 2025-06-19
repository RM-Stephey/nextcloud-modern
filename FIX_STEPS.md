# Nextcloud Configuration Fix Steps

This guide will help you resolve the remaining Nextcloud configuration issues.

## Current Issues
1. ❌ Trusted proxies not correctly set as array
2. ❌ .well-known URLs not resolving (webfinger)
3. ❌ HSTS header value too low

## Step 1: Apply the Configuration Fix

Run the following commands from the `nextcloud-modern` directory:

```bash
cd /path/to/th3tn/nextcloud-modern

# Make sure containers are running
docker-compose up -d

# Apply the configuration fix
./apply-config-fix.sh
```

This script will:
- Fix the trusted_proxies array configuration
- Set proper overwrite parameters
- Clear caches
- Restart the necessary containers

## Step 2: Update Your Edge Nginx Configuration

Replace your current edge nginx configuration with the fixed version:

```bash
# Backup your current config
sudo cp /etc/nginx/sites-available/cloud.stepheybot.dev /etc/nginx/sites-available/cloud.stepheybot.dev.backup

# Copy the new configuration
sudo cp ../edge-nginx-fixed.conf /etc/nginx/sites-available/cloud.stepheybot.dev

# Test the configuration
sudo nginx -t

# If test passes, reload nginx
sudo nginx -s reload
```

## Step 3: Verify Docker Network Configuration

Ensure your containers can communicate properly:

```bash
# Check the Docker network
docker network inspect nextcloud-modern_nextcloud_net

# Verify the web container is accessible from your edge server
curl -I http://m0th3r.munchkin-ray.ts.net:8080
```

## Step 4: Manual Config.php Verification (if needed)

If the automated fix doesn't work, manually check the config:

```bash
# Enter the container
docker exec -it nextcloud_app bash

# Check the config file
cat /var/www/html/config/config.php | grep -A 20 trusted_proxies

# Exit the container
exit
```

The `trusted_proxies` should be an array like this:
```php
'trusted_proxies' => 
array (
  0 => '10.0.0.0/8',
  1 => '172.16.0.0/12',
  2 => '192.168.0.0/16',
  3 => '100.64.0.0/10',
  // ... more entries
),
```

## Step 5: Test .well-known URLs

After applying the fixes, test the .well-known URLs:

```bash
# Test from the edge server
curl -I https://cloud.stepheybot.dev/.well-known/webfinger
curl -I https://cloud.stepheybot.dev/.well-known/carddav
curl -I https://cloud.stepheybot.dev/.well-known/caldav
```

You should get redirects (301/302) or successful responses (200).

## Step 6: Final Verification

1. Visit: https://cloud.stepheybot.dev/settings/admin/overview
2. Check that all warnings are resolved
3. If any persist, check the logs:
   ```bash
   docker-compose logs -f nextcloud
   docker-compose logs -f web
   ```

## Troubleshooting

### If trusted_proxies error persists:

1. The issue might be with environment variable parsing. Try setting it directly in config.php:
   ```bash
   docker exec -u www-data nextcloud_app php occ config:system:set trusted_proxies --type=json --value='["10.0.0.0/8","172.16.0.0/12","192.168.0.0/16","100.64.0.0/10","fd7a:115c:a1e0::/48"]'
   ```

2. Or manually edit the config file inside the container:
   ```bash
   docker exec -it nextcloud_app bash
   apt update && apt install -y nano
   nano /var/www/html/config/config.php
   # Edit the trusted_proxies to be a proper PHP array
   ```

### If .well-known URLs still fail:

1. Check if the internal nginx is receiving the requests:
   ```bash
   docker-compose logs -f web | grep well-known
   ```

2. Verify the proxy_pass is working:
   ```bash
   # From the edge server
   curl -v http://m0th3r.munchkin-ray.ts.net:8080/.well-known/webfinger
   ```

### If HSTS header is still showing as 0:

1. Clear your browser cache completely
2. Use curl to verify the header:
   ```bash
   curl -I https://cloud.stepheybot.dev | grep -i strict
   ```

## Expected Results

After completing these steps, you should see:
- ✅ No trusted_proxies warning
- ✅ All .well-known URLs resolving correctly
- ✅ HSTS header set to 31536000 seconds
- ✅ No security header warnings

## Notes

- The Tailscale IP range (100.64.0.0/10) is now included in trusted proxies
- The edge nginx now properly forwards .well-known requests to the backend
- HSTS is set at the edge nginx level with a 1-year duration
- All security headers are handled consistently between edge and internal nginx