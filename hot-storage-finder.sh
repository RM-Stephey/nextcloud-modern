#!/bin/bash

# Log file
LOG_FILE="/home/th3tn/nextcloud-modern/hot-storage.log"
echo "$(date): Starting hot storage file detection" >> "$LOG_FILE"

# Extract files with high access count from Nextcloud database
docker exec nextcloud_db psql -U nextcloud -d nextcloud -c "
  COPY (
    SELECT f.path, f.size, COUNT(a.file_path) as access_count
    FROM oc_filecache f
    JOIN oc_activity a ON a.file_path LIKE '%' || f.path
    WHERE a.type = 'file_access' AND f.size > 52428800
    GROUP BY f.path, f.size
    HAVING COUNT(a.file_path) > 5
    ORDER BY access_count DESC
    LIMIT 50
  ) TO STDOUT WITH CSV HEADER
" > /tmp/hot_files.csv

# Process each file
while IFS=, read -r path size count
do
  # Skip header
  if [ "$path" != "path" ]; then
    echo "$(date): Moving file: $path (accessed $count times)" >> "$LOG_FILE"

    # Extract filename
    filename=$(basename "$path")

    # Perform the move via Nextcloud occ command
    docker exec nextcloud_app sh -c "cd /var/www/html && php occ files:transfer --source=\"$path\" --destination=\"/MinIO Storage/$filename\" --user=admin"

    # Log the result
    if [ $? -eq 0 ]; then
      echo "$(date): Successfully moved $path to hot storage" >> "$LOG_FILE"
    else
      echo "$(date): Failed to move $path to hot storage" >> "$LOG_FILE"
    fi
  fi
done < /tmp/hot_files.csv

echo "$(date): Completed hot storage file detection" >> "$LOG_FILE"
