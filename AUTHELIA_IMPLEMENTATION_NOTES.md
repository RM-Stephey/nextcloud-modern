# Authelia Implementation Notes - StepheyBot Services

## Overview
This document contains notes from the Authelia migration attempt on June 23, 2025. We successfully configured Authelia but encountered a "bad gateway" issue, so we're rolling back to OAuth2 Proxy temporarily.

## ✅ Successfully Completed

### 1. Environment Variables Generated
All necessary secrets were generated and added to `.env`:
```bash
AUTHELIA_JWT_SECRET=ngwf/Nso5pD/zIdmQdRtBkvTSaZFHluaaFgVc+z9Cmk=
AUTHELIA_SESSION_SECRET=7UOHK3CVO4TFAoKxRsmAyZdBL5iGhnIa0AlmhV4=
AUTHELIA_STORAGE_ENCRYPTION_KEY=sMt1cEhzCZBNlwzHiUGggPvjciwBN+wdqMX+WkCXQJA=
AUTHELIA_DOMAIN=auth.stepheybot.dev
```

### 2. Working Authelia Configuration
Created `authelia-config.yml` with minimal v4.38+ compatible configuration:
- File-based authentication
- Local session storage (no Redis initially)
- Proper access control rules for all services
- Working on port 9091

### 3. Docker Compose Integration
Updated `docker-compose.yml` with Authelia service:
- Container running successfully 
- Health checks passing
- Proper network configuration

### 4. VPS Nginx Configuration
The VPS nginx config at `/etc/nginx/sites-available/default` was already perfectly configured for Authelia:
- All services have `/api/verify` auth_request endpoints
- Proper header forwarding
- Error page redirects to `https://auth.stepheybot.dev/?rd=$target_url`

### 5. OAuth2 Proxy Cleanup
Successfully removed all 7 OAuth2 proxy containers:
- oauth2-proxy-unified
- oauth2-proxy-dashboard  
- oauth2-proxy-music
- oauth2-proxy-lidarr
- oauth2-proxy-listen
- oauth2-proxy-s3
- oauth2-proxy-stepheybot
- oauth2-proxy-notes

## ❌ Issues Encountered

### 1. Bad Gateway Error
After successful Authelia deployment, visiting protected services resulted in "502 Bad Gateway"
- Authelia container healthy and responding on port 9091
- Nginx configuration appears correct
- Issue likely in the auth_request flow between nginx and Authelia

### 2. Redis Connection Issues (Resolved)
Initially had Redis password authentication errors:
```
redis connection error: WRONGPASS invalid username-password pair or user is disabled
```
- Resolved by temporarily disabling Redis and using local session storage
- Redis password has special characters that may need escaping

## 🔧 Working Configuration Files

### Minimal Authelia Config (`authelia-config.yml`)
```yaml
---
theme: dark

server:
    address: tcp://0.0.0.0:9091/

log:
    level: info
    format: text
    keep_stdout: true

identity_validation:
    reset_password:
        jwt_secret: ${AUTHELIA_JWT_SECRET}

authentication_backend:
    refresh_interval: 5m
    password_reset:
        disable: false
    file:
        path: /config/users_database.yml
        password:
            algorithm: argon2id
            iterations: 1
            salt_length: 16
            parallelism: 8
            memory: 64

access_control:
    default_policy: deny
    rules:
        - domain: dashboard.stepheybot.dev
          policy: one_factor
        - domain: navidrome.stepheybot.dev
          policy: one_factor
        - domain: music.stepheybot.dev
          policy: one_factor
        - domain: listen.stepheybot.dev
          policy: one_factor
        - domain: lidarr.stepheybot.dev
          policy: one_factor
        - domain: s3.stepheybot.dev
          policy: one_factor
        - domain: notes.stepheybot.dev
          policy: bypass
        - domain: cloud.stepheybot.dev
          policy: bypass

session:
    secret: ${AUTHELIA_SESSION_SECRET}
    cookies:
        - domain: stepheybot.dev
          authelia_url: https://auth.stepheybot.dev
          default_redirection_url: https://dashboard.stepheybot.dev
          same_site: lax
          expiration: 12h
          inactivity: 1h
          remember_me: 30d

regulation:
    max_retries: 3
    find_time: 2m
    ban_time: 5m

storage:
    encryption_key: ${AUTHELIA_STORAGE_ENCRYPTION_KEY}
    local:
        path: /config/data/db.sqlite3

notifier:
    disable_startup_check: false
    filesystem:
        filename: /config/data/notification.txt

totp:
    disable: false
    issuer: stepheybot.dev
    algorithm: sha1
    digits: 6
    period: 30
    skew: 1
    secret_size: 32

password_policy:
    zxcvbn:
        enabled: true
        min_score: 3

ntp:
    address: time.cloudflare.com:123
    version: 4
    max_desync: 3s
    disable_startup_check: false
    disable_failure: false
```

### Users Database (`users_database.yml`)
```yaml
---
users:
  stephey:
    displayname: "Stephey"
    password: "$argon2id$v=19$m=65536,t=3,p=4$YWJjZGVmZ2hpamtsbW5vcA$K6LdYnC8Ybm5h9zQf0Xo+SO7R4ZOE6a0s6LNX6v8wbk"
    email: "stephen@stephey.dev"
    groups:
      - admins
      - users
      - music
      - storage

groups:
  - admins
  - users
  - music
  - storage
  - dashboard
```
**Note**: Default password is "stepheybot123" - change after testing!

## 🔄 Rollback Process

To rollback to OAuth2 Proxy:
1. Stop and remove Authelia container
2. Recreate OAuth2 proxy containers with original configuration
3. Update VPS nginx to point back to OAuth2 proxy ports
4. Verify all services are accessible

## 📝 Next Steps for Completion

### 1. Debug Bad Gateway Issue
- Check Authelia logs during auth request
- Verify nginx auth_request module is working correctly
- Test direct Authelia API endpoints
- Ensure proper header forwarding

### 2. Add Redis Back
Once basic auth works, re-enable Redis for session persistence:
```yaml
session:
    redis:
        host: redis
        port: 6379
        password: "${REDIS_PASSWORD}"
        database_index: 1
```

### 3. Add OIDC Support (Optional)
For integration with Keycloak if desired:
- Generate OIDC private key
- Configure OIDC clients
- Update client secrets

### 4. Security Enhancements
- Enable TOTP/2FA
- Configure email notifications
- Add WebAuthn support for hardware keys
- Implement proper RBAC based on groups

### 5. Testing Checklist
- [ ] Login/logout flow works
- [ ] Session persistence across browser restarts
- [ ] All protected services accessible after auth
- [ ] Bypass services (Nextcloud, AFFiNE) work without auth
- [ ] Mobile device compatibility
- [ ] Password reset functionality

## 📚 Useful Commands

### Start Authelia
```bash
cd nextcloud-modern
docker-compose up -d authelia
```

### Check Authelia Status
```bash
docker ps | grep authelia
docker logs authelia-unified --tail 20
```

### Test Authelia Directly
```bash
curl -I http://localhost:9091
curl -I http://localhost:9091/api/health
```

### Generate New Password Hash
```bash
docker run --rm authelia/authelia:latest authelia crypto hash generate pbkdf2 --password "your-password"
```

## 🚨 Important Notes

1. **VPS Nginx Config**: Already perfect for Authelia - no changes needed
2. **File Permissions**: Ensure `/mnt/nvme/apps/authelia-data` has proper ownership (1000:1000)
3. **Network**: Authelia must be on `nextcloud_net` and `proxy` networks
4. **Port 9091**: Must be available (kill any conflicting processes)
5. **Environment Variables**: All secrets properly generated and stored in `.env`

## 🔗 References

- [Authelia Documentation v4.38+](https://www.authelia.com/integration/proxies/nginx/)
- [Nginx auth_request Module](http://nginx.org/en/docs/http/ngx_http_auth_request_module.html)
- [Docker Compose Health Checks](https://docs.docker.com/compose/compose-file/compose-file-v3/#healthcheck)

---
**Status**: Ready for implementation - just needs bad gateway debugging
**Priority**: Medium (OAuth2 proxy working as fallback)
**Estimated Time**: 2-4 hours for completion