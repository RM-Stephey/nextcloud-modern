# Modern High-Performance Nextcloud Setup Guide

This guide walks you through setting up a modern, high-performance Nextcloud instance optimized for your powerful hardware.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Performance Optimization](#performance-optimization)
- [Security Configuration](#security-configuration)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Hardware Requirements
- **CPU**: Multi-core processor (your i7-7700K is perfect)
- **RAM**: 16GB minimum (32GB recommended for optimal performance)
- **Storage**: 
  - SSD: 100GB+ for apps, database, and cache
  - HDD: As needed for user data (your 8TB drive)
- **GPU**: Optional, but beneficial for image processing (your GTX 1080)

### Software Requirements
- **OS**: Linux (CachyOS, Ubuntu 22.04+, Debian 11+)
- **Docker**: 24.0+ with Docker Compose v2
- **NVIDIA Docker**: For GPU acceleration (optional)

### Network Requirements
- **Domain**: A domain pointing to your server
- **Ports**: 80 and 443 open for HTTP/HTTPS

## Quick Start

1. **Clone or create the configuration**:
   ```bash
   mkdir -p ~/nextcloud-modern
   cd ~/nextcloud-modern
   # Copy all configuration files here
   ```

2. **Create storage directories**:
   ```bash
   # On your SSD
   sudo mkdir -p /mnt/ssd/nextcloud/{nextcloud_app,nextcloud_db,nextcloud_redis,nextcloud_elastic}
   
   # On your HDD
   sudo mkdir -p /mnt/hdd/{nextcloud_data,media,backups/nextcloud}
   
   # Set permissions
   sudo chown -R 33:0 /mnt/hdd/nextcloud_data
   sudo chmod -R 750 /mnt/hdd/nextcloud_data
   ```

3. **Configure environment**:
   ```bash
   cp .env.template .env
   # Edit .env with your settings
   nano .env
   ```

4. **Start the stack**:
   ```bash
   docker-compose up -d
   ```

5. **Access Nextcloud**:
   - Visit: https://cloud.stepheybot.dev
   - Login with your admin credentials

## Detailed Setup

### 1. Storage Configuration

#### SSD Setup (for performance-critical data)
```bash
# Create directories for Docker volumes
sudo mkdir -p /mnt/ssd/nextcloud/{nextcloud_app,nextcloud_db,nextcloud_redis,nextcloud_elastic}

# Ensure correct ownership
sudo chown -R 999:999 /mnt/ssd/nextcloud/nextcloud_db  # PostgreSQL
sudo chown -R 999:999 /mnt/ssd/nextcloud/nextcloud_redis  # Redis
```

#### HDD Setup (for user data)
```bash
# Create data directory
sudo mkdir -p /mnt/hdd/nextcloud_data

# Set ownership for www-data (UID 33)
sudo chown -R 33:0 /mnt/hdd/nextcloud_data
sudo chmod -R 750 /mnt/hdd/nextcloud_data
```

### 2. Environment Configuration

Edit `.env` file with your specific settings:

```env
# Critical settings to change:
DB_PASSWORD=<generate-strong-password>
REDIS_PASSWORD=<generate-strong-password>
ADMIN_PASSWORD=<your-admin-password>
ADMIN_EMAIL=your-email@example.com
PRIMARY_DOMAIN=cloud.stepheybot.dev

# Storage paths - adjust to your setup
SSD_APP_PATH=/mnt/ssd/nextcloud
DATA_DIR=/mnt/hdd/nextcloud_data
BACKUP_DIR=/mnt/hdd/backups/nextcloud
```

### 3. GPU Setup (Optional)

For NVIDIA GPU acceleration:

```bash
# Install NVIDIA Docker runtime
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt update && sudo apt install -y nvidia-docker2
sudo systemctl restart docker
```

### 4. Initial Deployment

```bash
# Start core services first
docker-compose up -d db redis

# Wait for database to initialize
sleep 30

# Start remaining services
docker-compose up -d

# Monitor logs
docker-compose logs -f
```

## Performance Optimization

### 1. PostgreSQL Tuning

The configuration includes optimizations for your 32GB RAM:
- **Shared buffers**: 4GB (12.5% of RAM)
- **Effective cache size**: 12GB (37.5% of RAM)
- **Work memory**: 128MB per operation
- **Parallel workers**: 8 (matching your CPU cores)

### 2. PHP-FPM Optimization

Create `php-fpm-custom.conf`:
```ini
[www]
pm = dynamic
pm.max_children = 120
pm.start_servers = 12
pm.min_spare_servers = 6
pm.max_spare_servers = 18
pm.max_requests = 1000
```

Mount in docker-compose.yml:
```yaml
volumes:
  - ./php-fpm-custom.conf:/usr/local/etc/php-fpm.d/zz-custom.conf
```

### 3. Redis Optimization

Current settings allocate 2GB for caching with LRU eviction. For your setup, you could increase to 4GB:
```yaml
command: redis-server --requirepass ${REDIS_PASSWORD} --maxmemory 4gb
```

### 4. Nextcloud Configuration

After installation, run these optimizations:

```bash
# Enter the container
docker exec -it nextcloud_app sh

# Enable recommended apps
php occ app:enable files_external
php occ app:enable richdocuments
php occ app:enable preview_generator
php occ app:enable fulltextsearch
php occ app:enable fulltextsearch_elasticsearch

# Configure preview generation
php occ config:app:set preview max_x --value 2048
php occ config:app:set preview max_y --value 2048
php occ config:system:set preview_max_memory --value 4096
php occ config:system:set enabledPreviewProviders 0 --value "OC\Preview\PNG"
php occ config:system:set enabledPreviewProviders 1 --value "OC\Preview\JPEG"
php occ config:system:set enabledPreviewProviders 2 --value "OC\Preview\GIF"
php occ config:system:set enabledPreviewProviders 3 --value "OC\Preview\BMP"
php occ config:system:set enabledPreviewProviders 4 --value "OC\Preview\HEIC"
php occ config:system:set enabledPreviewProviders 5 --value "OC\Preview\MarkDown"
php occ config:system:set enabledPreviewProviders 6 --value "OC\Preview\MP3"
php occ config:system:set enabledPreviewProviders 7 --value "OC\Preview\TXT"
php occ config:system:set enabledPreviewProviders 8 --value "OC\Preview\Movie"

# Configure Imaginary for preview generation
php occ config:system:set preview_imaginary_url --value "http://imaginary:8088"

# Set memory limits
php occ config:system:set memory_limit --value 4G

# Configure background jobs
php occ config:system:set backgroundjobs_mode --value cron
```

### 5. Elasticsearch Configuration

```bash
# Configure full-text search
docker exec -it nextcloud_app sh
php occ fulltextsearch:configure '{"search_platform":"OCA\\FullTextSearch_Elasticsearch\\Platform\\ElasticSearchPlatform"}'
php occ fulltextsearch_elasticsearch:configure '{"elastic_host":"http://elasticsearch:9200"}'
php occ fulltextsearch:index
```

## Security Configuration

### 1. Firewall Rules

```bash
# Allow only necessary ports
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

### 2. Fail2ban Integration

Create `/etc/fail2ban/jail.d/nextcloud.conf`:
```ini
[nextcloud]
enabled = true
port = 80,443
protocol = tcp
filter = nextcloud
maxretry = 3
bantime = 86400
findtime = 3600
logpath = /mnt/ssd/nextcloud/nextcloud_app/data/nextcloud.log
```

### 3. SSL Configuration

Caddy automatically handles SSL certificates. For additional security, add to Caddyfile:
```
tls {
    protocols tls1.2 tls1.3
    ciphers TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
}
```

## Maintenance

### Daily Tasks (Automated)
- Preview generation (via preview_generator container)
- Database backups (via backup container)
- Cron jobs (via cron container)

### Weekly Tasks
```bash
# Update all containers
docker-compose pull
docker-compose up -d

# Clean up Docker
docker system prune -a -f --volumes
```

### Monthly Tasks
```bash
# Nextcloud maintenance
docker exec -it nextcloud_app php occ files:scan --all
docker exec -it nextcloud_app php occ files:cleanup
docker exec -it nextcloud_app php occ maintenance:repair

# Database optimization
docker exec -it nextcloud_db psql -U nextcloud -c "VACUUM ANALYZE;"
```

## Troubleshooting

### Common Issues

#### 1. 502 Bad Gateway
```bash
# Check if services are running
docker-compose ps

# Check nginx logs
docker logs nextcloud_web

# Check Caddy logs
docker logs nextcloud_caddy
```

#### 2. Slow Performance
```bash
# Check resource usage
docker stats

# Enable APCu cache
docker exec -it nextcloud_app php occ config:system:set memcache.local --value '\OC\Memcache\APCu'
```

#### 3. Database Connection Issues
```bash
# Test database connection
docker exec -it nextcloud_app php occ db:info

# Check database logs
docker logs nextcloud_db
```

#### 4. Redis Connection Issues
```bash
# Test Redis connection
docker exec -it nextcloud_redis redis-cli -a ${REDIS_PASSWORD} ping

# Should return: PONG
```

### Debug Mode

Enable debug mode for troubleshooting:
```bash
docker exec -it nextcloud_app php occ config:system:set debug --value true
docker exec -it nextcloud_app php occ config:system:set loglevel --value 0
```

Remember to disable after troubleshooting:
```bash
docker exec -it nextcloud_app php occ config:system:set debug --value false
docker exec -it nextcloud_app php occ config:system:set loglevel --value 2
```

## Advanced Features

### 1. External Storage

```bash
# Enable external storage
docker exec -it nextcloud_app php occ app:enable files_external

# Add SMB/CIFS share
docker exec -it nextcloud_app php occ files_external:create \
  "SharedDrive" smb password::password \
  -c host=192.168.1.100 \
  -c share=ShareName \
  -c domain=WORKGROUP \
  --user myuser
```

### 2. Collabora Integration

After deployment:
1. Visit Nextcloud admin panel
2. Install "Nextcloud Office" app
3. Configure Collabora URL: `https://collabora.cloud.stepheybot.dev`

### 3. Talk (Video Calls)

For video calls, you'll need a TURN server:
```yaml
# Add to docker-compose.yml
coturn:
  image: coturn/coturn:latest
  container_name: nextcloud_turn
  restart: unless-stopped
  ports:
    - "3478:3478/tcp"
    - "3478:3478/udp"
  environment:
    - DETECT_EXTERNAL_IP=yes
    - DETECT_RELAY_IP=yes
    - EXTERNAL_IP=${PUBLIC_IP}
```

## Monitoring

### 1. System Metrics

```bash
# Install monitoring stack (optional)
docker run -d \
  --name nextcloud_monitor \
  -p 3000:3000 \
  -v grafana-storage:/var/lib/grafana \
  grafana/grafana
```

### 2. Nextcloud Metrics

```bash
# Enable metrics app
docker exec -it nextcloud_app php occ app:enable serverinfo

# Access metrics
curl -u admin:password https://cloud.stepheybot.dev/ocs/v2.php/apps/serverinfo/api/v1/info
```

## Backup Strategy

### Automated Backups

The backup container runs daily at 2 AM. To manually trigger:
```bash
docker exec nextcloud_backup backup
```

### Manual Backup

```bash
# Database
docker exec nextcloud_db pg_dump -U nextcloud nextcloud > backup.sql

# Files
tar -czf nextcloud-data-$(date +%Y%m%d).tar.gz /mnt/hdd/nextcloud_data

# Config
docker exec nextcloud_app php occ config:list system > config-backup.json
```

### Restore Process

```bash
# Stop services
docker-compose stop app

# Restore database
docker exec -i nextcloud_db psql -U nextcloud nextcloud < backup.sql

# Restore files
tar -xzf nextcloud-data-20231201.tar.gz -C /

# Start services
docker-compose start app
```

## Performance Benchmarks

Test your setup performance:
```bash
# File upload speed
time docker exec nextcloud_app php occ files:scan --all

# Database performance
docker exec nextcloud_db pgbench -U nextcloud -d nextcloud -c 10 -t 100

# Redis performance
docker exec nextcloud_redis redis-benchmark -a ${REDIS_PASSWORD}
```

## Support

- **Nextcloud Documentation**: https://docs.nextcloud.com
- **Community Forum**: https://help.nextcloud.com
- **GitHub Issues**: https://github.com/nextcloud/server/issues

Remember to keep your system updated and monitor logs regularly for optimal performance and security!