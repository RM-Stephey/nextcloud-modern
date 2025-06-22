#!/bin/bash

# Configuration
HOT_STORAGE_PATH="/mnt/nvme/hot"
DAYS_THRESHOLD=30
LOG_FILE="/var/log/hot-storage-cleanup.log"

# Log function
log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

log_message "Starting hot storage cleanup"

# Find files not accessed in the last 30 days
OLD_FILES=$(find $HOT_STORAGE_PATH -type f -atime +$DAYS_THRESHOLD)

# Count files to be removed
COUNT=$(echo "$OLD_FILES" | grep -v "^$" | wc -l)
log_message "Found $COUNT files that haven't been accessed in $DAYS_THRESHOLD days"

# Process each file
echo "$OLD_FILES" | while read file; do
  if [ -z "$file" ]; then
    continue
  fi
  
  # Get file size before removal
  SIZE=$(du -h "$file" | cut -f1)
  FILENAME=$(basename "$file")
  
  # Check if the file is currently in use
  if lsof "$file" > /dev/null 2>&1; then
    log_message "Skipping file in use: $FILENAME ($SIZE)"
    continue
  fi

  # Before removing, sync with Nextcloud if needed
  docker exec -it nextcloud_app sh -c "cd /var/www/html && php occ files:scan --path=\"/MinIO Storage/$FILENAME\""
  
  # Remove the file
  rm "$file"
  log_message "Removed $FILENAME ($SIZE)"
done

log_message "Hot storage cleanup completed"
