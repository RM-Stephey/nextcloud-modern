# Nextcloud Update Checklist

## Before You Update

### 🔍 Pre-Update Checks

- [ ] **Check current version**: Verify you're on Nextcloud 29.x
  ```bash
  docker exec -u www-data nextcloud_app php occ status
  ```

- [ ] **Check system requirements**: Nextcloud 30 requires:
  - PHP 8.1 or higher (satisfied by Docker image)
  - PostgreSQL 11 or higher (you have 16 ✓)
  - Redis 5.0 or higher (you have 7 ✓)

- [ ] **Review breaking changes**: Check [Nextcloud 30 changelog](https://nextcloud.com/changelog/)

- [ ] **Verify disk space**: Ensure you have at least 10GB free for backups
  ```bash
  df -h /mnt/ssd /mnt/hdd
  ```

- [ ] **Check app compatibility**: Some apps might need updates
  ```bash
  docker exec -u www-data nextcloud_app php occ app:list
  ```

### 📋 Update Process

1. **Make the update script executable**:
   ```bash
   chmod +x update-nextcloud.sh
   ```

2. **Run the update script**:
   ```bash
   ./update-nextcloud.sh
   ```

3. **Monitor the update process** - The script will:
   - Enable maintenance mode
   - Backup database and config
   - Update Docker images
   - Run Nextcloud upgrade
   - Perform database optimizations
   - Disable maintenance mode

### ⚠️ Important Notes

- **Estimated downtime**: 10-30 minutes depending on database size
- **Backup location**: `./backups/update-[timestamp]/`
- **Rollback available**: Use the restore script if needed

### 🔄 Post-Update Tasks

After the update completes:

1. **Check admin overview**:
   - Visit https://cloud.stepheybot.dev/settings/admin/overview
   - Resolve any new warnings

2. **Test core functionality**:
   - [ ] File upload/download
   - [ ] WebDAV access
   - [ ] Calendar/Contacts sync
   - [ ] Collabora Online (if used)
   - [ ] Talk (if used)

3. **Update apps**:
   ```bash
   docker exec -u www-data nextcloud_app php occ app:update --all
   ```

4. **Re-scan files** (if needed):
   ```bash
   docker exec -u www-data nextcloud_app php occ files:scan --all
   ```

### 🚨 Rollback Procedure

If something goes wrong:

1. **Navigate to backup directory**:
   ```bash
   cd ./backups/update-[timestamp]/
   ```

2. **Run restore script**:
   ```bash
   ./restore.sh
   ```

3. **Verify restoration**:
   - Check that you're back on version 29
   - Verify data integrity
   - Check functionality

### 📊 Performance Considerations

Nextcloud 30 includes performance improvements:
- Better handling of large file uploads
- Improved search performance
- Enhanced caching mechanisms

Your setup with Redis and PostgreSQL optimizations should see benefits.

### 🔒 Security Notes

Nextcloud 30 includes security enhancements:
- Improved password policies
- Enhanced brute-force protection
- Better session management

These should work well with your existing reverse proxy setup.

## Ready to Update?

If all checks pass, proceed with:
```bash
./update-nextcloud.sh
```

Good luck! 🚀