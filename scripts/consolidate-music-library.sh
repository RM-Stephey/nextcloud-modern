#!/bin/bash

# StepheyBot Music - Smart Library Consolidation & Organization Script
# Consolidates flat library into professional Artist/Album structure with tiered storage

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
FLAT_SOURCE="/mnt/hdd/media/music/library-flat-backup"
ORGANIZED_TARGET="/mnt/hdd/media/music/library"
NVME_CACHE="/mnt/nvme/hot/stepheybot-music-cache"
PROCESSING_DIR="/mnt/nvme/upload/processing"
DATABASE_DIR="/mnt/hdd/media/music/databases"
INDEX_DIR="/mnt/hdd/media/music/indexes"
LOG_FILE="/mnt/hdd/media/music/organization.log"

# Create necessary directories
mkdir -p "$ORGANIZED_TARGET" "$NVME_CACHE" "$PROCESSING_DIR" "$DATABASE_DIR" "$INDEX_DIR"

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to sanitize filenames for filesystem
sanitize_filename() {
    echo "$1" | sed 's/[<>:"/\\|?*]/_/g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//'
}

# Function to extract metadata using ffprobe
get_metadata() {
    local file="$1"
    local tag="$2"

    ffprobe -v quiet -show_entries format_tags="$tag" -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | head -1
}

# Function to get metadata with fallback to filename parsing
get_artist_album_title() {
    local file="$1"
    local filename=$(basename "$file" .mp3)

    # Try to get from ID3 tags first
    local artist=$(get_metadata "$file" "artist")
    local album=$(get_metadata "$file" "album")
    local title=$(get_metadata "$file" "title")

    # Fallback to filename parsing if metadata is missing
    if [[ -z "$artist" || -z "$title" ]]; then
        if [[ "$filename" =~ ^(.+)\ -\ (.+)$ ]]; then
            [[ -z "$artist" ]] && artist="${BASH_REMATCH[1]}"
            [[ -z "$title" ]] && title="${BASH_REMATCH[2]}"
        else
            [[ -z "$artist" ]] && artist="Unknown Artist"
            [[ -z "$title" ]] && title="$filename"
        fi
    fi

    # Default album if missing
    [[ -z "$album" ]] && album="Singles"

    echo "$artist|$album|$title"
}

# Function to calculate file hash for deduplication
calculate_hash() {
    local file="$1"
    md5sum "$file" | cut -d' ' -f1
}

# Function to organize a single file
organize_file() {
    local source_file="$1"
    local filename=$(basename "$source_file")

    # Skip non-music files
    if [[ ! "$filename" =~ \.(mp3|flac|m4a|wav)$ ]]; then
        warn "Skipping non-music file: $filename"
        return 0
    fi

    # Get metadata
    local metadata=$(get_artist_album_title "$source_file")
    local artist=$(echo "$metadata" | cut -d'|' -f1)
    local album=$(echo "$metadata" | cut -d'|' -f2)
    local title=$(echo "$metadata" | cut -d'|' -f3)

    # Sanitize for filesystem
    local safe_artist=$(sanitize_filename "$artist")
    local safe_album=$(sanitize_filename "$album")
    local safe_title=$(sanitize_filename "$title")

    # Create target directory structure
    local target_dir="$ORGANIZED_TARGET/$safe_artist/$safe_album"
    mkdir -p "$target_dir"

    # Determine target filename
    local extension="${filename##*.}"
    local target_file="$target_dir/$safe_title.$extension"

    # Handle duplicates
    local counter=1
    while [[ -f "$target_file" ]]; do
        local existing_hash=$(calculate_hash "$target_file")
        local new_hash=$(calculate_hash "$source_file")

        if [[ "$existing_hash" == "$new_hash" ]]; then
            info "Duplicate found (same hash): $filename -> skipping"
            return 0
        else
            target_file="$target_dir/$safe_title ($counter).$extension"
            ((counter++))
        fi
    done

    # Copy file (preserve metadata)
    if cp -p "$source_file" "$target_file"; then
        info "Organized: $filename -> $safe_artist/$safe_album/"

        # Add to index
        echo "$target_file|$artist|$album|$title|$(date +%s)|$(calculate_hash "$target_file")" >> "$INDEX_DIR/library_index.txt"

        return 0
    else
        error "Failed to copy: $filename"
        return 1
    fi
}

# Function to create library database
create_library_database() {
    log "Creating library database..."

    local db_file="$DATABASE_DIR/library.db"

    # Create SQLite database
    sqlite3 "$db_file" <<EOF
CREATE TABLE IF NOT EXISTS tracks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT UNIQUE NOT NULL,
    artist TEXT NOT NULL,
    album TEXT NOT NULL,
    title TEXT NOT NULL,
    duration INTEGER,
    file_size INTEGER,
    file_hash TEXT UNIQUE,
    date_added INTEGER,
    last_played INTEGER,
    play_count INTEGER DEFAULT 0,
    rating INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_artist ON tracks(artist);
CREATE INDEX IF NOT EXISTS idx_album ON tracks(album);
CREATE INDEX IF NOT EXISTS idx_title ON tracks(title);
CREATE INDEX IF NOT EXISTS idx_hash ON tracks(file_hash);

-- Full-text search index
CREATE VIRTUAL TABLE IF NOT EXISTS tracks_fts USING fts5(
    artist, album, title, content='tracks', content_rowid='id'
);

-- Populate FTS from main table
INSERT OR REPLACE INTO tracks_fts(rowid, artist, album, title)
SELECT id, artist, album, title FROM tracks;
EOF

    success "Library database created: $db_file"
}

# Function to populate database from organized files
populate_database() {
    log "Populating database with organized files..."

    local db_file="$DATABASE_DIR/library.db"
    local temp_sql="/tmp/populate_db.sql"

    echo "BEGIN TRANSACTION;" > "$temp_sql"

    find "$ORGANIZED_TARGET" -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.wav" | while read -r file; do
        local metadata=$(get_artist_album_title "$file")
        local artist=$(echo "$metadata" | cut -d'|' -f1 | sed "s/'/''/g")
        local album=$(echo "$metadata" | cut -d'|' -f2 | sed "s/'/''/g")
        local title=$(echo "$metadata" | cut -d'|' -f3 | sed "s/'/''/g")
        local file_size=$(stat -c%s "$file")
        local file_hash=$(calculate_hash "$file")
        local date_added=$(date +%s)

        # Get duration if possible
        local duration=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | cut -d. -f1)
        [[ -z "$duration" ]] && duration=0

        echo "INSERT OR REPLACE INTO tracks (file_path, artist, album, title, duration, file_size, file_hash, date_added) VALUES ('$file', '$artist', '$album', '$title', $duration, $file_size, '$file_hash', $date_added);" >> "$temp_sql"
    done

    echo "COMMIT;" >> "$temp_sql"
    echo "INSERT OR REPLACE INTO tracks_fts(rowid, artist, album, title) SELECT id, artist, album, title FROM tracks;" >> "$temp_sql"

    sqlite3 "$db_file" < "$temp_sql"
    rm "$temp_sql"

    success "Database populated with track information"
}

# Function to create smart cache system
setup_smart_cache() {
    log "Setting up smart NVME cache system..."

    # Create cache directories
    mkdir -p "$NVME_CACHE"/{hot,warm,processing}

    # Create cache index
    touch "$NVME_CACHE/cache_index.txt"

    # Create cache management script
    cat > "$NVME_CACHE/manage_cache.sh" <<'CACHE_EOF'
#!/bin/bash
# Smart cache management for StepheyBot Music

CACHE_DIR="/mnt/nvme/hot/stepheybot-music-cache"
MAX_CACHE_SIZE_GB=50
LIBRARY_DIR="/mnt/hdd/media/music/library"

# Function to get cache size in GB
get_cache_size() {
    du -sb "$CACHE_DIR" | cut -f1 | awk '{print int($1/1024/1024/1024)}'
}

# Function to cache a file
cache_file() {
    local source="$1"
    local relative_path="${source#$LIBRARY_DIR/}"
    local cache_target="$CACHE_DIR/hot/$relative_path"

    mkdir -p "$(dirname "$cache_target")"

    if [[ ! -f "$cache_target" ]]; then
        cp "$source" "$cache_target"
        echo "$(date +%s)|$cache_target" >> "$CACHE_DIR/cache_index.txt"
    fi
}

# Function to clean old cache files
cleanup_cache() {
    local current_size=$(get_cache_size)

    if [[ $current_size -gt $MAX_CACHE_SIZE_GB ]]; then
        echo "Cache size ($current_size GB) exceeds limit ($MAX_CACHE_SIZE_GB GB). Cleaning..."

        # Remove oldest cached files
        sort -n "$CACHE_DIR/cache_index.txt" | head -n 100 | while read -r line; do
            local timestamp=$(echo "$line" | cut -d'|' -f1)
            local file=$(echo "$line" | cut -d'|' -f2)

            if [[ -f "$file" ]]; then
                rm "$file"
                # Remove from index
                grep -v "$file" "$CACHE_DIR/cache_index.txt" > "$CACHE_DIR/cache_index.tmp"
                mv "$CACHE_DIR/cache_index.tmp" "$CACHE_DIR/cache_index.txt"
            fi
        done
    fi
}

# Run cleanup
cleanup_cache
CACHE_EOF

    chmod +x "$NVME_CACHE/manage_cache.sh"

    success "Smart cache system configured"
}

# Function to create deduplication index
create_dedup_index() {
    log "Creating deduplication index..."

    local dedup_file="$INDEX_DIR/dedup_index.txt"

    # Create hash index of all files
    find "$ORGANIZED_TARGET" -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.wav" | while read -r file; do
        local hash=$(calculate_hash "$file")
        local relative_path="${file#$ORGANIZED_TARGET/}"
        echo "$hash|$relative_path" >> "$dedup_file"
    done

    success "Deduplication index created: $dedup_file"
}

# Function to create search optimization
create_search_index() {
    log "Creating search optimization indexes..."

    # Artist index
    sqlite3 "$DATABASE_DIR/library.db" "SELECT DISTINCT artist FROM tracks ORDER BY artist;" > "$INDEX_DIR/artists.txt"

    # Album index
    sqlite3 "$DATABASE_DIR/library.db" "SELECT DISTINCT album FROM tracks ORDER BY album;" > "$INDEX_DIR/albums.txt"

    # Genre index (if available)
    # This would need to be populated from metadata

    success "Search indexes created"
}

# Function to generate statistics
generate_stats() {
    log "Generating library statistics..."

    local stats_file="$INDEX_DIR/library_stats.json"
    local total_files=$(find "$ORGANIZED_TARGET" -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.wav" | wc -l)
    local total_artists=$(sqlite3 "$DATABASE_DIR/library.db" "SELECT COUNT(DISTINCT artist) FROM tracks;")
    local total_albums=$(sqlite3 "$DATABASE_DIR/library.db" "SELECT COUNT(DISTINCT album) FROM tracks;")
    local total_size=$(du -sb "$ORGANIZED_TARGET" | cut -f1)

    cat > "$stats_file" <<EOF
{
    "total_tracks": $total_files,
    "total_artists": $total_artists,
    "total_albums": $total_albums,
    "total_size_bytes": $total_size,
    "total_size_human": "$(numfmt --to=iec-i --suffix=B $total_size)",
    "last_updated": $(date +%s),
    "organization_complete": true,
    "tiered_storage_enabled": true,
    "deduplication_enabled": true
}
EOF

    success "Library statistics generated: $stats_file"

    # Display summary
    echo
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}             STEPHEYBOT MUSIC LIBRARY SUMMARY              ${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}📊 Total Tracks:${NC} $total_files"
    echo -e "${CYAN}🎤 Total Artists:${NC} $total_artists"
    echo -e "${CYAN}💿 Total Albums:${NC} $total_albums"
    echo -e "${CYAN}📦 Total Size:${NC} $(numfmt --to=iec-i --suffix=B $total_size)"
    echo -e "${CYAN}🗄️  Master Library:${NC} $ORGANIZED_TARGET"
    echo -e "${CYAN}⚡ NVME Cache:${NC} $NVME_CACHE"
    echo -e "${CYAN}🗃️  Database:${NC} $DATABASE_DIR/library.db"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════${NC}"
    echo
}

# Main consolidation function
main() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              STEPHEYBOT MUSIC LIBRARY CONSOLIDATOR          ║"
    echo "║                     Smart Organization                       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Check if source exists
    if [[ ! -d "$FLAT_SOURCE" ]]; then
        error "Source directory not found: $FLAT_SOURCE"
        exit 1
    fi

    # Count source files
    local source_count=$(find "$FLAT_SOURCE" -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.wav" | wc -l)
    log "Found $source_count music files to organize"

    # Check for existing organized library
    if [[ -d "$ORGANIZED_TARGET" ]] && [[ -n "$(ls -A "$ORGANIZED_TARGET" 2>/dev/null)" ]]; then
        warn "Target directory exists and is not empty: $ORGANIZED_TARGET"
        read -p "Continue and merge? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Operation cancelled by user"
            exit 0
        fi
    fi

    # Backup existing if it exists
    if [[ -d "$ORGANIZED_TARGET" ]]; then
        log "Backing up existing organized library..."
        mv "$ORGANIZED_TARGET" "${ORGANIZED_TARGET}-backup-$(date +%Y%m%d-%H%M%S)"
    fi

    mkdir -p "$ORGANIZED_TARGET"

    log "Starting organization process..."

    # Initialize progress tracking
    local processed=0
    local failed=0

    # Process files
    while IFS= read -r -d '' file; do
        if organize_file "$file"; then
            ((processed++))
        else
            ((failed++))
        fi

        # Progress indicator
        if (( processed % 50 == 0 )); then
            info "Processed $processed files..."
        fi
    done < <(find "$FLAT_SOURCE" -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.wav" -print0)

    log "Organization complete. Processed: $processed, Failed: $failed"

    # Set up database and indexes
    create_library_database
    populate_database
    create_dedup_index
    create_search_index
    setup_smart_cache

    # Generate final statistics
    generate_stats

    success "Library consolidation complete!"

    # Cleanup recommendations
    echo
    echo -e "${YELLOW}🔧 NEXT STEPS:${NC}"
    echo "1. Update docker-compose.yml to point to: $ORGANIZED_TARGET"
    echo "2. Restart Navidrome: docker-compose restart navidrome"
    echo "3. Restart StepheyBot Music: docker-compose restart stepheybot-music"
    echo "4. Run library scan: curl -X POST http://localhost:8083/api/v1/library/scan"
    echo "5. Verify no duplicates: ./scripts/verify-library.sh"
    echo
    echo -e "${GREEN}✅ Your music library is now professionally organized!${NC}"
}

# Run main function
main "$@"
