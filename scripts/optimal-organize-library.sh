#!/bin/bash

# StepheyBot Music - Optimal Library Organization Script
# Creates professional Artist/Album structure using real file copies
# Optimized for media servers, Docker containers, and streaming performance

set -u

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Configuration
FLAT_SOURCE="/mnt/hdd/media/music/library-flat-backup"
ORGANIZED_TARGET="/mnt/hdd/media/music/library"
NVME_CACHE="/mnt/nvme/hot/stepheybot-music-cache"
PROCESSING_DIR="/mnt/nvme/upload/processing"
DATABASE_DIR="/mnt/hdd/media/music/databases"
INDEX_DIR="/mnt/hdd/media/music/indexes"
LOG_FILE="/mnt/hdd/media/music/optimal-organization.log"

# Statistics
TOTAL_FILES=0
PROCESSED_FILES=0
ORGANIZED_FILES=0
FAILED_FILES=0
SKIPPED_FILES=0
ARTISTS_CREATED=0
ALBUMS_CREATED=0
DUPLICATES_FOUND=0
TOTAL_SIZE=0
START_TIME=$(date +%s)

# Progress tracking
CURRENT_PHASE=""
PHASE_PROGRESS=0
PHASE_TOTAL=0

# Create necessary directories
mkdir -p "$ORGANIZED_TARGET" "$NVME_CACHE" "$PROCESSING_DIR" "$DATABASE_DIR" "$INDEX_DIR"

# Logging functions with real-time display
log() {
    local message="$1"
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $message" | tee -a "$LOG_FILE"
}

error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
}

success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$LOG_FILE"
}

warn() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$LOG_FILE"
}

info() {
    local message="$1"
    echo -e "${CYAN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
}

progress() {
    local message="$1"
    echo -e "${WHITE}[PROGRESS]${NC} $message" | tee -a "$LOG_FILE"
}

# Function to display current phase and progress
update_progress() {
    local current="$1"
    local total="$2"
    local item="$3"

    PHASE_PROGRESS=$current
    PHASE_TOTAL=$total

    local percentage=$((current * 100 / total))
    local elapsed=$(($(date +%s) - START_TIME))
    local eta=""

    if [[ $current -gt 0 ]]; then
        local rate=$((current / (elapsed + 1)))
        local remaining=$((total - current))
        local eta_seconds=$((remaining / (rate + 1)))
        eta=" ETA: ${eta_seconds}s"
    fi

    progress "${CURRENT_PHASE}: [$current/$total] ${percentage}%${eta} - Processing: $(basename "$item")"
}

# Function to sanitize filenames for filesystem
sanitize_filename() {
    echo "$1" | \
        sed 's/[<>:"/\\|?*]/_/g' | \
        sed 's/[[:space:]]\+/ /g' | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
        sed 's/\.$/_/g' | \
        sed 's/^\./_/'
}

# Function to parse artist and title from filename
parse_filename() {
    local filename="$1"
    local basename="${filename%.*}"

    # Remove common prefixes
    basename=$(echo "$basename" | sed 's/^[0-9]\+[[:space:]]*-[[:space:]]*//')

    # Handle various artist-title separators
    if [[ "$basename" =~ ^(.+)[[:space:]]*-[[:space:]]*(.+)$ ]]; then
        local artist="${BASH_REMATCH[1]}"
        local title="${BASH_REMATCH[2]}"

        # Clean up artist name - handle collaborations
        if [[ "$artist" =~ ^(.+)[[:space:]]*,[[:space:]]*(.+)$ ]]; then
            # Primary artist, collaborator format
            artist="${BASH_REMATCH[1]}"
        elif [[ "$artist" =~ ^(.+)[[:space:]]+feat\.?[[:space:]]+(.+)$ ]]; then
            # Handle "feat." in artist name
            artist="${BASH_REMATCH[1]}"
        fi

        # Clean up title - remove remix/edit info for album determination
        title=$(echo "$title" | sed 's/[[:space:]]*$//;s/^[[:space:]]*//')

        echo "$artist|$title"
    else
        # No separator found, treat as title with unknown artist
        echo "Unknown Artist|$basename"
    fi
}

# Function to determine album name intelligently
determine_album() {
    local artist="$1"
    local title="$2"
    local original_filename="$3"

    # Look for remix/edit indicators
    if [[ "$title" =~ [Rr]emix|[Mm]ix|[Ee]dit|[Rr]ework ]]; then
        echo "Remixes & Edits"
        return
    fi

    # Look for live/acoustic indicators
    if [[ "$title" =~ [Ll]ive|[Aa]coustic|[Uu]nplugged ]]; then
        echo "Live & Acoustic"
        return
    fi

    # Look for compilation indicators
    if [[ "$original_filename" =~ [Cc]ompilation|[Cc]ollection|[Bb]est[[:space:]][Oo]f|[Hh]its ]]; then
        echo "Compilations"
        return
    fi

    # Look for extended/radio edit indicators
    if [[ "$title" =~ [Ee]xtended|[Rr]adio[[:space:]][Ee]dit ]]; then
        echo "Singles & Edits"
        return
    fi

    # Default to Singles
    echo "Singles"
}

# Function to calculate file hash for deduplication
calculate_hash() {
    local file="$1"
    md5sum "$file" 2>/dev/null | cut -d' ' -f1 || echo "unknown"
}

# Function to organize a single file
organize_file() {
    local source_file="$1"
    local index="$2"
    local total="$3"
    local filename=$(basename "$source_file")

    update_progress "$index" "$total" "$source_file"

    # Skip non-music files
    if [[ ! "$filename" =~ \.(mp3|flac|m4a|wav|ogg|wma|aac)$ ]]; then
        warn "Skipping non-music file: $filename"
        ((SKIPPED_FILES++))
        return 0
    fi

    # Check file size (skip if too small - likely corrupted)
    local file_size=$(stat -c%s "$source_file" 2>/dev/null || echo 0)
    if [[ $file_size -lt 1000 ]]; then
        warn "Skipping tiny file (likely corrupted): $filename"
        ((SKIPPED_FILES++))
        return 0
    fi

    # Parse filename
    local metadata=$(parse_filename "$filename")
    local artist=$(echo "$metadata" | cut -d'|' -f1)
    local title=$(echo "$metadata" | cut -d'|' -f2)

    # Determine album
    local album=$(determine_album "$artist" "$title" "$filename")

    # Sanitize for filesystem
    local safe_artist=$(sanitize_filename "$artist")
    local safe_album=$(sanitize_filename "$album")
    local safe_title=$(sanitize_filename "$title")

    # Create target directory structure
    local artist_dir="$ORGANIZED_TARGET/$safe_artist"
    local album_dir="$artist_dir/$safe_album"

    # Create directories if they don't exist
    if [[ ! -d "$artist_dir" ]]; then
        mkdir -p "$artist_dir"
        ((ARTISTS_CREATED++))
        info "Created artist directory: $safe_artist"
    fi

    if [[ ! -d "$album_dir" ]]; then
        mkdir -p "$album_dir"
        ((ALBUMS_CREATED++))
    fi

    # Determine target filename
    local extension="${filename##*.}"
    local target_file="$album_dir/$safe_title.$extension"

    # Handle duplicates
    local counter=1
    while [[ -f "$target_file" ]]; do
        local existing_hash=$(calculate_hash "$target_file")
        local new_hash=$(calculate_hash "$source_file")

        if [[ "$existing_hash" == "$new_hash" ]]; then
            info "Duplicate found (same content): $filename -> skipping"
            ((DUPLICATES_FOUND++))
            ((PROCESSED_FILES++))
            return 0
        else
            target_file="$album_dir/$safe_title ($counter).$extension"
            ((counter++))
        fi
    done

    # Copy file (preserve metadata and timestamps)
    if cp -p "$source_file" "$target_file"; then
        ((ORGANIZED_FILES++))
        ((TOTAL_SIZE+=file_size))

        # Add to index for database population
        echo "$target_file|$artist|$album|$title|$(date +%s)|$file_size|$(calculate_hash "$target_file")" >> "$INDEX_DIR/organized_files.txt"

        # Progress indicator for every 50 files
        if (( ORGANIZED_FILES % 50 == 0 )); then
            local mb_processed=$((TOTAL_SIZE / 1024 / 1024))
            info "Milestone: $ORGANIZED_FILES files organized, ${mb_processed}MB processed"
        fi

        ((PROCESSED_FILES++))
        return 0
    else
        error "Failed to copy: $filename"
        ((FAILED_FILES++))
        ((PROCESSED_FILES++))
        return 1
    fi
}

# Function to create library database with progress reporting
create_library_database() {
    CURRENT_PHASE="Creating Database Schema"
    log "Creating optimized library database..."

    local db_file="$DATABASE_DIR/library.db"

    # Remove existing database for clean start
    rm -f "$db_file"

    progress "Creating database tables and indexes..."

    # Create SQLite database with optimized schema
    sqlite3 "$db_file" <<'EOF'
-- Enable WAL mode for better performance
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA cache_size=10000;
PRAGMA temp_store=memory;

-- Create main tracks table
CREATE TABLE tracks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT UNIQUE NOT NULL,
    artist TEXT NOT NULL,
    album TEXT NOT NULL,
    title TEXT NOT NULL,
    file_extension TEXT,
    file_size INTEGER,
    file_hash TEXT,
    date_added INTEGER,
    last_played INTEGER DEFAULT 0,
    play_count INTEGER DEFAULT 0,
    rating INTEGER DEFAULT 0,
    duration INTEGER DEFAULT 0,
    bitrate INTEGER DEFAULT 0,
    sample_rate INTEGER DEFAULT 0
);

-- Create performance indexes
CREATE INDEX idx_artist ON tracks(artist);
CREATE INDEX idx_album ON tracks(album);
CREATE INDEX idx_title ON tracks(title);
CREATE INDEX idx_artist_album ON tracks(artist, album);
CREATE INDEX idx_file_hash ON tracks(file_hash);
CREATE INDEX idx_date_added ON tracks(date_added);
CREATE INDEX idx_play_count ON tracks(play_count);

-- Create full-text search index
CREATE VIRTUAL TABLE tracks_fts USING fts5(
    artist, album, title,
    content='tracks',
    content_rowid='id'
);

-- Create artists summary table
CREATE TABLE artists (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    normalized_name TEXT,
    album_count INTEGER DEFAULT 0,
    track_count INTEGER DEFAULT 0,
    total_duration INTEGER DEFAULT 0,
    total_size INTEGER DEFAULT 0,
    first_added INTEGER,
    last_added INTEGER,
    play_count INTEGER DEFAULT 0
);

-- Create albums summary table
CREATE TABLE albums (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    normalized_title TEXT,
    track_count INTEGER DEFAULT 0,
    total_duration INTEGER DEFAULT 0,
    total_size INTEGER DEFAULT 0,
    date_added INTEGER,
    play_count INTEGER DEFAULT 0,
    UNIQUE(title, artist)
);

-- Create library statistics table
CREATE TABLE library_stats (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    total_tracks INTEGER DEFAULT 0,
    total_artists INTEGER DEFAULT 0,
    total_albums INTEGER DEFAULT 0,
    total_size INTEGER DEFAULT 0,
    total_duration INTEGER DEFAULT 0,
    last_updated INTEGER,
    last_scan INTEGER,
    organization_method TEXT DEFAULT 'real_copy',
    deduplication_enabled BOOLEAN DEFAULT 1
);

-- Create deduplication tracking table
CREATE TABLE file_hashes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_hash TEXT UNIQUE NOT NULL,
    file_path TEXT NOT NULL,
    file_size INTEGER,
    first_seen INTEGER,
    reference_count INTEGER DEFAULT 1
);

-- Create search cache for performance
CREATE TABLE search_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    query_hash TEXT UNIQUE NOT NULL,
    query_text TEXT NOT NULL,
    result_count INTEGER,
    cached_results TEXT,
    created_at INTEGER,
    last_accessed INTEGER,
    access_count INTEGER DEFAULT 1
);

-- Insert initial statistics
INSERT INTO library_stats (id, last_updated, organization_method) VALUES (1, strftime('%s', 'now'), 'real_copy');

EOF

    success "Database schema created: $db_file"
}

# Function to populate database from organized files
populate_database() {
    CURRENT_PHASE="Populating Database"
    log "Populating database with organized files..."

    local db_file="$DATABASE_DIR/library.db"
    local index_file="$INDEX_DIR/organized_files.txt"

    if [[ ! -f "$index_file" ]]; then
        warn "No organized files index found"
        return 1
    fi

    local total_records=$(wc -l < "$index_file")
    progress "Preparing to import $total_records tracks into database..."

    local temp_sql="/tmp/populate_library.sql"
    local current_record=0

    echo "BEGIN TRANSACTION;" > "$temp_sql"

    while IFS='|' read -r file_path artist album title date_added file_size file_hash; do
        ((current_record++))

        if (( current_record % 100 == 0 )); then
            update_progress "$current_record" "$total_records" "$file_path"
        fi

        # Escape single quotes for SQL
        artist=$(echo "$artist" | sed "s/'/''/g")
        album=$(echo "$album" | sed "s/'/''/g")
        title=$(echo "$title" | sed "s/'/''/g")
        file_path=$(echo "$file_path" | sed "s/'/''/g")

        # Get file extension
        local extension="${file_path##*.}"

        # Insert track record
        echo "INSERT OR REPLACE INTO tracks (file_path, artist, album, title, file_extension, file_size, file_hash, date_added) VALUES ('$file_path', '$artist', '$album', '$title', '$extension', $file_size, '$file_hash', $date_added);" >> "$temp_sql"

        # Insert hash record for deduplication
        echo "INSERT OR IGNORE INTO file_hashes (file_hash, file_path, file_size, first_seen) VALUES ('$file_hash', '$file_path', $file_size, $date_added);" >> "$temp_sql"

    done < "$index_file"

    progress "Updating summary statistics and indexes..."

    # Update FTS index
    echo "INSERT INTO tracks_fts(rowid, artist, album, title) SELECT id, artist, album, title FROM tracks;" >> "$temp_sql"

    # Update artists table
    echo "INSERT OR REPLACE INTO artists (name, normalized_name, album_count, track_count, total_size, first_added, last_added) SELECT artist, LOWER(artist), COUNT(DISTINCT album), COUNT(*), SUM(file_size), MIN(date_added), MAX(date_added) FROM tracks GROUP BY artist;" >> "$temp_sql"

    # Update albums table
    echo "INSERT OR REPLACE INTO albums (title, artist, normalized_title, track_count, total_size, date_added) SELECT album, artist, LOWER(album), COUNT(*), SUM(file_size), MIN(date_added) FROM tracks GROUP BY artist, album;" >> "$temp_sql"

    # Update library statistics
    echo "UPDATE library_stats SET total_tracks = (SELECT COUNT(*) FROM tracks), total_artists = (SELECT COUNT(DISTINCT artist) FROM tracks), total_albums = (SELECT COUNT(DISTINCT artist || '|' || album) FROM tracks), total_size = (SELECT SUM(file_size) FROM tracks), last_updated = strftime('%s', 'now'), last_scan = strftime('%s', 'now') WHERE id = 1;" >> "$temp_sql"

    echo "COMMIT;" >> "$temp_sql"

    progress "Executing database import (this may take a moment)..."

    # Execute SQL
    if sqlite3 "$db_file" < "$temp_sql"; then
        rm -f "$temp_sql"
        success "Database populated with $current_record tracks"
    else
        error "Database population failed"
        return 1
    fi
}

# Function to create search optimization indexes
create_search_indexes() {
    CURRENT_PHASE="Creating Search Indexes"
    log "Creating search optimization indexes..."

    local db_file="$DATABASE_DIR/library.db"

    progress "Exporting search-friendly indexes..."

    # Export various indexes for quick access
    sqlite3 "$db_file" "SELECT DISTINCT artist FROM tracks ORDER BY artist COLLATE NOCASE;" > "$INDEX_DIR/artists.txt"
    sqlite3 "$db_file" "SELECT DISTINCT album FROM tracks ORDER BY album COLLATE NOCASE;" > "$INDEX_DIR/albums.txt"
    sqlite3 "$db_file" "SELECT DISTINCT title FROM tracks ORDER BY title COLLATE NOCASE;" > "$INDEX_DIR/titles.txt"

    # Create artist-album mapping for quick lookups
    sqlite3 "$db_file" "SELECT artist || '|' || album FROM tracks GROUP BY artist, album ORDER BY artist COLLATE NOCASE, album COLLATE NOCASE;" > "$INDEX_DIR/artist_albums.txt"

    # Create popular tracks index (by hypothetical play count)
    sqlite3 "$db_file" "SELECT artist || ' - ' || title FROM tracks ORDER BY play_count DESC, artist COLLATE NOCASE LIMIT 1000;" > "$INDEX_DIR/popular_tracks.txt"

    # Create file extension summary
    sqlite3 "$db_file" "SELECT file_extension, COUNT(*) FROM tracks GROUP BY file_extension ORDER BY COUNT(*) DESC;" > "$INDEX_DIR/file_formats.txt"

    success "Search indexes created in $INDEX_DIR"
}

# Function to create deduplication report
create_dedup_report() {
    CURRENT_PHASE="Creating Deduplication Report"
    log "Creating deduplication analysis..."

    local db_file="$DATABASE_DIR/library.db"
    local dedup_report="$INDEX_DIR/deduplication_report.txt"

    progress "Analyzing duplicate files..."

    # Find potential duplicates by hash
    sqlite3 "$db_file" "SELECT file_hash, COUNT(*) as count, GROUP_CONCAT(file_path, ' | ') as files FROM file_hashes WHERE file_hash != 'unknown' GROUP BY file_hash HAVING count > 1;" > "$dedup_report"

    local duplicate_groups=$(wc -l < "$dedup_report" || echo 0)

    if [[ $duplicate_groups -gt 0 ]]; then
        warn "Found $duplicate_groups groups of duplicate files - see $dedup_report"
    else
        success "No duplicate files found - library is clean!"
    fi
}

# Function to setup cache management
setup_cache_management() {
    CURRENT_PHASE="Setting Up Cache Management"
    log "Setting up intelligent cache management..."

    mkdir -p "$NVME_CACHE"/{hot,warm,recent}

    progress "Creating cache management script..."

    # Create sophisticated cache management script
    cat > "$NVME_CACHE/manage_cache.sh" <<'CACHE_SCRIPT'
#!/bin/bash
# Intelligent cache management for StepheyBot Music

CACHE_DIR="/mnt/nvme/hot/stepheybot-music-cache"
LIBRARY_DIR="/mnt/hdd/media/music/library"
DATABASE="/mnt/hdd/media/music/databases/library.db"
MAX_CACHE_SIZE_GB=30
LOG_FILE="/mnt/hdd/media/music/cache_management.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to get cache size in GB
get_cache_size() {
    du -sb "$CACHE_DIR" 2>/dev/null | cut -f1 | awk '{print int($1/1024/1024/1024)}'
}

# Pre-cache popular artists and recent additions
precache_content() {
    log "Starting intelligent pre-caching..."

    # Cache top 5 artists by track count
    sqlite3 "$DATABASE" "SELECT name FROM artists ORDER BY track_count DESC LIMIT 5;" | while read -r artist; do
        find "$LIBRARY_DIR/$artist" -name "*.mp3" -o -name "*.flac" | head -10 | while read -r file; do
            local cache_path="$CACHE_DIR/hot/${file#$LIBRARY_DIR/}"

            if [[ ! -f "$cache_path" ]] && [[ -f "$file" ]]; then
                mkdir -p "$(dirname "$cache_path")"
                cp "$file" "$cache_path" 2>/dev/null && log "Cached: $(basename "$file")"
            fi
        done
    done

    # Cache recently added tracks
    sqlite3 "$DATABASE" "SELECT file_path FROM tracks ORDER BY date_added DESC LIMIT 20;" | while read -r file; do
        local cache_path="$CACHE_DIR/recent/${file#$LIBRARY_DIR/}"

        if [[ ! -f "$cache_path" ]] && [[ -f "$file" ]]; then
            mkdir -p "$(dirname "$cache_path")"
            cp "$file" "$cache_path" 2>/dev/null && log "Cached recent: $(basename "$file")"
        fi
    done
}

# Clean old cache files when size limit exceeded
cleanup_cache() {
    local current_size=$(get_cache_size)

    if [[ $current_size -gt $MAX_CACHE_SIZE_GB ]]; then
        log "Cache size ($current_size GB) exceeds limit ($MAX_CACHE_SIZE_GB GB). Cleaning..."

        # Remove files older than 7 days from warm cache
        find "$CACHE_DIR/warm" -type f -mtime +7 -delete 2>/dev/null

        # Remove files older than 3 days from recent cache
        find "$CACHE_DIR/recent" -type f -mtime +3 -delete 2>/dev/null

        # Keep hot cache but remove oldest files if still over limit
        current_size=$(get_cache_size)
        if [[ $current_size -gt $MAX_CACHE_SIZE_GB ]]; then
            find "$CACHE_DIR/hot" -type f -printf '%T@ %p\n' | sort -n | head -50 | cut -d' ' -f2- | xargs rm -f 2>/dev/null
        fi

        log "Cache cleanup completed. New size: $(get_cache_size) GB"
    fi
}

# Main execution
log "Cache management started"
precache_content
cleanup_cache
log "Cache management completed"
CACHE_SCRIPT

    chmod +x "$NVME_CACHE/manage_cache.sh"

    success "Cache management system configured"
}

# Function to update docker configuration
update_docker_configuration() {
    CURRENT_PHASE="Updating Docker Configuration"
    log "Updating Docker Compose configuration..."

    local compose_file="/home/th3tn/nextcloud-modern/docker-compose.yml"

    if [[ -f "$compose_file" ]]; then
        progress "Backing up existing docker-compose.yml..."
        cp "$compose_file" "$compose_file.backup-$(date +%Y%m%d-%H%M%S)"

        progress "Updating volume mounts to use organized library..."
        # Update both Navidrome and StepheyBot Music to use organized structure
        sed -i "s|/mnt/nvme/hot/stepheybot-music-org/organized:/music:ro|$ORGANIZED_TARGET:/music:ro|g" "$compose_file"
        sed -i "s|/mnt/hdd/media/music/library-flat-backup:/music:ro|$ORGANIZED_TARGET:/music:ro|g" "$compose_file"

        success "Docker configuration updated"
    else
        warn "Docker-compose file not found at $compose_file"
    fi
}

# Function to generate comprehensive statistics
generate_final_statistics() {
    CURRENT_PHASE="Generating Statistics"
    log "Generating comprehensive library statistics..."

    local stats_file="$INDEX_DIR/final_statistics.json"
    local db_file="$DATABASE_DIR/library.db"
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))

    progress "Calculating final statistics..."

    # Get database statistics
    local db_tracks=$(sqlite3 "$db_file" "SELECT COUNT(*) FROM tracks;" 2>/dev/null || echo 0)
    local db_artists=$(sqlite3 "$db_file" "SELECT COUNT(DISTINCT artist) FROM tracks;" 2>/dev/null || echo 0)
    local db_albums=$(sqlite3 "$db_file" "SELECT COUNT(DISTINCT artist || '|' || album) FROM tracks;" 2>/dev/null || echo 0)
    local db_size=$(sqlite3 "$db_file" "SELECT SUM(file_size) FROM tracks;" 2>/dev/null || echo 0)

    # Format sizes
    local total_size_mb=$((TOTAL_SIZE / 1024 / 1024))
    local total_size_gb=$((TOTAL_SIZE / 1024 / 1024 / 1024))

    # Calculate success rate
    local success_rate="0"
    if [[ $TOTAL_FILES -gt 0 ]]; then
        success_rate=$(echo "scale=2; $ORGANIZED_FILES * 100 / $TOTAL_FILES" | bc -l 2>/dev/null || echo "0")
    fi

    cat > "$stats_file" <<EOF
{
    "organization_summary": {
        "method": "real_copy",
        "start_time": "$START_TIME",
        "end_time": "$end_time",
        "duration_seconds": $total_duration,
        "duration_human": "$(($total_duration / 3600))h $(($total_duration % 3600 / 60))m $(($total_duration % 60))s"
    },
    "file_processing": {
        "total_files_found": $TOTAL_FILES,
        "successfully_organized": $ORGANIZED_FILES,
        "failed_files": $FAILED_FILES,
        "skipped_files": $SKIPPED_FILES,
        "duplicates_found": $DUPLICATES_FOUND,
        "success_rate": "${success_rate}%"
    },
    "library_structure": {
        "artists_created": $ARTISTS_CREATED,
        "albums_created": $ALBUMS_CREATED,
        "directory_structure": "Artist/Album/Title.ext"
    },
    "storage_analysis": {
        "total_size_bytes": $TOTAL_SIZE,
        "total_size_mb": $total_size_mb,
        "total_size_gb": $total_size_gb,
        "average_file_size_mb": $(echo "scale=2; $total_size_mb / $ORGANIZED_FILES" | bc -l 2>/dev/null || echo "0")
    },
    "database_statistics": {
        "tracks_in_db": $db_tracks,
        "artists_in_db": $db_artists,
        "albums_in_db": $db_albums,
        "total_size_in_db": $db_size,
        "fts_enabled": true,
        "deduplication_enabled": true
    },
    "paths": {
        "source_library": "$FLAT_SOURCE",
        "organized_library": "$ORGANIZED_TARGET",
        "database_directory": "$DATABASE_DIR",
        "index_directory": "$INDEX_DIR",
        "cache_directory": "$NVME_CACHE"
    },
    "features_enabled": {
        "tiered_storage": true,
        "smart_caching": true,
        "full_text_search": true,
        "deduplication": true,
        "docker_integration": true
    }
}
EOF

    success "Final statistics generated: $stats_file"

    # Display beautiful summary
    echo
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                    STEPHEYBOT MUSIC ORGANIZATION COMPLETE                   ║${NC}"
    echo -e "${PURPLE}║                           Optimal Real-Copy Method                          ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${CYAN}📊 PROCESSING SUMMARY:${NC}"
    echo -e "   📁 Total Files Found: ${WHITE}$TOTAL_FILES${NC}"
    echo -e "   ✅ Successfully Organized: ${GREEN}$ORGANIZED_FILES${NC}"
    echo -e "   ❌ Failed: ${RED}$FAILED_FILES${NC}"
    echo -e "   ⏭️  Skipped: ${YELLOW}$SKIPPED_FILES${NC}"
    echo -e "   🔍 Duplicates Found: ${YELLOW}$DUPLICATES_FOUND${NC}"
    echo -e "   📈 Success Rate: ${GREEN}${success_rate}%${NC}"
    echo
    echo -e "${CYAN}🎵 LIBRARY STRUCTURE:${NC}"
    echo -e "   🎤 Artists Created: ${WHITE}$ARTISTS_CREATED${NC}"
    echo -e "   💿 Albums Created: ${WHITE}$ALBUMS_CREATED${NC}"
    echo -e "   📁 Organization: ${WHITE}Artist/Album/Title.ext${NC}"
    echo
    echo -e "${CYAN}💾 STORAGE ANALYSIS:${NC}"
    echo -e "   📦 Total Size: ${WHITE}${total_size_gb}GB${NC} (${total_size_mb}MB)"
    echo -e "   📄 Average File Size: ${WHITE}$(echo "scale=1; $total_size_mb / $ORGANIZED_FILES" | bc -l 2>/dev/null || echo "N/A")MB${NC}"
    echo -e "   🗄️  Master Library: ${WHITE}$ORGANIZED_TARGET${NC}"
    echo
    echo -e "${CYAN}🗃️  DATABASE & INDEXES:${NC}"
    echo -e "   🔍 Tracks in Database: ${WHITE}$db_tracks${NC}"
    echo -e "   🎭 Artists in Database: ${WHITE}$db_artists${NC}"
    echo -e "   📀 Albums in Database: ${WHITE}$db_albums${NC}"
    echo -e "   ⚡ Full-Text Search: ${GREEN}Enabled${NC}"
    echo -e "   🔄 Deduplication: ${GREEN}Enabled${NC}"
    echo
    echo -e "${CYAN}⏱️  PERFORMANCE:${NC}"
    echo -e "   🕐 Total Duration: ${WHITE}$(($total_duration / 3600))h $(($total_duration % 3600 / 60))m $(($total_duration % 60))s${NC}"
    echo -e "   ⚡ Processing Rate: ${WHITE}$(echo "scale=1; $ORGANIZED_FILES * 3600 / $total_duration" | bc -l 2>/dev/null || echo "N/A") files/hour${NC}"
    echo
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
}

# Function to display next steps
show_next_steps() {
    echo
    echo -e "${YELLOW}🔧 NEXT STEPS TO COMPLETE SETUP:${NC}"
    echo
    echo -e "${WHITE}1. Restart Services:${NC}"
    echo "   docker-compose restart navidrome stepheybot-music"
    echo
    echo -e "${WHITE}2. Trigger Library Scan:${NC}"
    echo "   curl -X POST http://localhost:8083/api/v1/library/scan"
    echo
    echo -e "${WHITE}3. Test Search Functionality:${NC}"
    echo "   curl 'http://localhost:8083/api/v1/search/local/ABBA'"
    echo
    echo -e "${WHITE}4. Initialize Cache:${NC}"
    echo "   $NVME_CACHE/manage_cache.sh"
    echo
    echo -e "${WHITE}5. Verify Organization:${NC}"
    echo "   ls -la '$ORGANIZED_TARGET'"
    echo
    echo -e "${GREEN}✨ Your StepheyBot Music library is now optimally organized!${NC}"
    echo -e "${CYAN}🎯 Features enabled: Tiered storage, Smart caching, FTS search, Deduplication${NC}"
    echo -e "${CYAN}🚀 Ready for high-performance music streaming and discovery!${NC}"
    echo
}

# Main function
main() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                    STEPHEYBOT MUSIC OPTIMAL ORGANIZATION                    ║"
    echo "║                        Professional Real-Copy Solution                      ║"
    echo "║                     🎵 Maximum Compatibility & Performance 🎵               ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Pre-flight checks
    if [[ ! -d "$FLAT_SOURCE" ]]; then
        error "Source directory not found: $FLAT_SOURCE"
        echo "Please ensure the flat library backup exists before running this script."
        exit 1
    fi

    # Check for required tools
    if ! command -v sqlite3 >/dev/null 2>&1; then
        error "SQLite3 is required but not installed"
        exit 1
    fi

    if ! command -v bc >/dev/null 2>&1; then
        warn "bc calculator not found - some statistics may be unavailable"
    fi

    # Count source files using array to avoid subshell issues
    log "Scanning source directory for music files..."
    mapfile -t all_music_files < <(find "$FLAT_SOURCE" -maxdepth 1 -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.wav" -o -name "*.ogg" -o -name "*.wma" -o -name "*.aac" \))
    TOTAL_FILES=${#all_music_files[@]}

    if [[ $TOTAL_FILES -eq 0 ]]; then
        error "No music files found in source directory"
        exit 1
    fi

    success "Found $TOTAL_FILES music files to organize"

    # Confirm operation
    echo
    echo -e "${YELLOW}⚠️  IMPORTANT: This operation will:${NC}"
    echo "   • Create organized copies of all music files (~13GB additional space)"
    echo "   • Replace any existing organized library"
    echo "   • Create a comprehensive database and search indexes"
    echo "   • Update Docker configuration for seamless integration"
    echo
    read -p "Continue with organization? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Operation cancelled by user"
        exit 0
    fi

    # Clean existing organized directory
    if [[ -d "$ORGANIZED_TARGET" ]]; then
        log "Backing up existing organized library..."
        mv "$ORGANIZED_TARGET" "${ORGANIZED_TARGET}-backup-$(date +%Y%m%d-%H%M%S)"
    fi

    # Create directory structure
    mkdir -p "$ORGANIZED_TARGET" "$DATABASE_DIR" "$INDEX_DIR" "$NVME_CACHE"

    # Phase 1: File Organization
    CURRENT_PHASE="File Organization"
    log "Starting intelligent file organization..."

    # Initialize index file
    echo "# Organized files index - generated $(date)" > "$INDEX_DIR/organized_files.txt"

    # Process all music files using the already-built array
    local file_index=0
    progress "Processing $TOTAL_FILES files..."

    for file in "${all_music_files[@]}"; do
        ((file_index++))
        organize_file "$file" "$file_index" "$TOTAL_FILES"
    done

    # Wait for all background processes
    wait

    log "File organization phase complete"

    # Phase 2: Database Setup
    create_library_database
    populate_database

    # Phase 3: Search Optimization
    create_search_indexes
    create_dedup_report

    # Phase 4: Cache Management
    setup_cache_management

    # Phase 5: Docker Integration
    update_docker_configuration

    # Phase 6: Final Statistics
    generate_final_statistics

    # Show completion and next steps
    show_next_steps

    success "StepheyBot Music optimal organization completed successfully!"

    # Log completion
    echo "$(date): Optimal organization completed - $ORGANIZED_FILES files organized" >> "$LOG_FILE"
}

# Cleanup function for interruption handling
cleanup() {
    echo
    warn "Organization interrupted - cleaning up..."

    # Remove incomplete database
    rm -f "$DATABASE_DIR/library.db" 2>/dev/null

    # Remove partial index files
    rm -f "$INDEX_DIR/organized_files.txt" 2>/dev/null

    echo "Cleanup completed. You can safely re-run the script."
    exit 1
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Run main function with all arguments
main "$@"
