#!/bin/bash

# StepheyBot Music - Quick Library Organization Script
# Creates organized Artist/Album structure using symlinks (no file duplication)

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
DATABASE_DIR="/mnt/hdd/media/music/databases"
INDEX_DIR="/mnt/hdd/media/music/indexes"
LOG_FILE="/mnt/hdd/media/music/quick-organization.log"

# Statistics
TOTAL_FILES=0
ORGANIZED_FILES=0
FAILED_FILES=0
ARTISTS_CREATED=0
ALBUMS_CREATED=0

# Create necessary directories
mkdir -p "$ORGANIZED_TARGET" "$NVME_CACHE" "$DATABASE_DIR" "$INDEX_DIR"

# Logging functions
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
    echo "$1" | \
        sed 's/[<>:"/\\|?*]/_/g' | \
        sed 's/[[:space:]]\+/ /g' | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
        sed 's/\.$/_/g'
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

        # Clean up artist name
        artist=$(echo "$artist" | sed 's/[[:space:]]*$//;s/^[[:space:]]*//')

        # Handle featuring and collaborations in artist
        if [[ "$artist" =~ ^(.+)[[:space:]]*,[[:space:]]*(.+)$ ]]; then
            # Primary artist, collaborator format
            artist="${BASH_REMATCH[1]}"
        fi

        # Clean up title
        title=$(echo "$title" | sed 's/[[:space:]]*$//;s/^[[:space:]]*//')

        echo "$artist|$title"
    else
        # No separator found, treat as title with unknown artist
        echo "Unknown Artist|$basename"
    fi
}

# Function to determine album name from patterns
determine_album() {
    local artist="$1"
    local title="$2"
    local original_filename="$3"

    # Look for remix indicators
    if [[ "$title" =~ [Rr]emix|[Mm]ix|[Ee]dit ]]; then
        echo "Remixes & Edits"
        return
    fi

    # Look for live/acoustic indicators
    if [[ "$title" =~ [Ll]ive|[Aa]coustic ]]; then
        echo "Live & Acoustic"
        return
    fi

    # Look for compilation indicators
    if [[ "$original_filename" =~ [Cc]ompilation|[Cc]ollection|[Bb]est[[:space:]][Oo]f ]]; then
        echo "Compilations"
        return
    fi

    # Default to Singles
    echo "Singles"
}

# Function to create symlink with proper structure
create_organized_symlink() {
    local source_file="$1"
    local filename=$(basename "$source_file")

    # Skip non-music files
    if [[ ! "$filename" =~ \.(mp3|flac|m4a|wav|ogg|wma)$ ]]; then
        warn "Skipping non-music file: $filename"
        return 1
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
    while [[ -e "$target_file" ]]; do
        target_file="$album_dir/$safe_title ($counter).$extension"
        ((counter++))
    done

    # Create symlink
    if ln -s "$source_file" "$target_file"; then
        ((ORGANIZED_FILES++))

        # Add to index for search optimization
        echo "$target_file|$artist|$album|$title|$(date +%s)|symlink" >> "$INDEX_DIR/organized_index.txt"

        return 0
    else
        error "Failed to create symlink: $filename"
        ((FAILED_FILES++))
        return 1
    fi
}

# Function to create library database
create_library_database() {
    log "Creating library database..."

    local db_file="$DATABASE_DIR/library.db"

    # Create SQLite database
    sqlite3 "$db_file" <<'EOF'
-- Drop existing tables if they exist
DROP TABLE IF EXISTS tracks_fts;
DROP TABLE IF EXISTS tracks;

-- Create main tracks table
CREATE TABLE tracks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT UNIQUE NOT NULL,
    symlink_target TEXT,
    artist TEXT NOT NULL,
    album TEXT NOT NULL,
    title TEXT NOT NULL,
    file_extension TEXT,
    file_size INTEGER,
    date_added INTEGER,
    last_played INTEGER DEFAULT 0,
    play_count INTEGER DEFAULT 0,
    rating INTEGER DEFAULT 0,
    is_symlink BOOLEAN DEFAULT 0
);

-- Create indexes for performance
CREATE INDEX idx_artist ON tracks(artist);
CREATE INDEX idx_album ON tracks(album);
CREATE INDEX idx_title ON tracks(title);
CREATE INDEX idx_artist_album ON tracks(artist, album);

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
    album_count INTEGER DEFAULT 0,
    track_count INTEGER DEFAULT 0,
    total_duration INTEGER DEFAULT 0,
    first_added INTEGER,
    last_added INTEGER
);

-- Create albums summary table
CREATE TABLE albums (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    track_count INTEGER DEFAULT 0,
    total_duration INTEGER DEFAULT 0,
    date_added INTEGER,
    UNIQUE(title, artist)
);

-- Create library statistics table
CREATE TABLE library_stats (
    id INTEGER PRIMARY KEY,
    total_tracks INTEGER DEFAULT 0,
    total_artists INTEGER DEFAULT 0,
    total_albums INTEGER DEFAULT 0,
    total_size INTEGER DEFAULT 0,
    last_updated INTEGER,
    organization_method TEXT DEFAULT 'symlink'
);

EOF

    success "Library database created: $db_file"
}

# Function to populate database from organized structure
populate_database() {
    log "Populating database with organized files..."

    local db_file="$DATABASE_DIR/library.db"
    local temp_sql="/tmp/populate_library.sql"
    local track_count=0

    echo "BEGIN TRANSACTION;" > "$temp_sql"

    # Process all symlinks in organized structure
    find "$ORGANIZED_TARGET" -type l \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.wav" -o -name "*.ogg" \) | while read -r symlink_path; do
        local target_path=$(readlink "$symlink_path")
        local relative_path="${symlink_path#$ORGANIZED_TARGET/}"

        # Parse path structure: Artist/Album/Title.ext
        local artist_album_title="${relative_path%/*}"
        local artist="${artist_album_title%/*}"
        local album="${artist_album_title##*/}"
        local filename=$(basename "$symlink_path")
        local title="${filename%.*}"
        local extension="${filename##*.}"

        # Get file size
        local file_size=0
        if [[ -f "$target_path" ]]; then
            file_size=$(stat -c%s "$target_path" 2>/dev/null || echo 0)
        fi

        local date_added=$(date +%s)

        # Escape single quotes for SQL
        artist=$(echo "$artist" | sed "s/'/''/g")
        album=$(echo "$album" | sed "s/'/''/g")
        title=$(echo "$title" | sed "s/'/''/g")
        symlink_path=$(echo "$symlink_path" | sed "s/'/''/g")
        target_path=$(echo "$target_path" | sed "s/'/''/g")

        echo "INSERT OR REPLACE INTO tracks (file_path, symlink_target, artist, album, title, file_extension, file_size, date_added, is_symlink) VALUES ('$symlink_path', '$target_path', '$artist', '$album', '$title', '$extension', $file_size, $date_added, 1);" >> "$temp_sql"

        ((track_count++))
    done

    # Update FTS index
    echo "INSERT INTO tracks_fts(rowid, artist, album, title) SELECT id, artist, album, title FROM tracks;" >> "$temp_sql"

    # Update statistics
    echo "INSERT OR REPLACE INTO library_stats (id, total_tracks, total_artists, total_albums, total_size, last_updated, organization_method) VALUES (1, (SELECT COUNT(*) FROM tracks), (SELECT COUNT(DISTINCT artist) FROM tracks), (SELECT COUNT(DISTINCT artist || '|' || album) FROM tracks), (SELECT SUM(file_size) FROM tracks), $(date +%s), 'symlink');" >> "$temp_sql"

    # Update artists table
    echo "INSERT OR REPLACE INTO artists (name, album_count, track_count, first_added, last_added) SELECT artist, COUNT(DISTINCT album), COUNT(*), MIN(date_added), MAX(date_added) FROM tracks GROUP BY artist;" >> "$temp_sql"

    # Update albums table
    echo "INSERT OR REPLACE INTO albums (title, artist, track_count, date_added) SELECT album, artist, COUNT(*), MIN(date_added) FROM tracks GROUP BY artist, album;" >> "$temp_sql"

    echo "COMMIT;" >> "$temp_sql"

    # Execute SQL
    sqlite3 "$db_file" < "$temp_sql"
    rm -f "$temp_sql"

    success "Database populated with $track_count tracks"
}

# Function to create search indexes
create_search_indexes() {
    log "Creating search optimization indexes..."

    local db_file="$DATABASE_DIR/library.db"

    # Export search-friendly indexes
    sqlite3 "$db_file" "SELECT DISTINCT artist FROM tracks ORDER BY artist;" > "$INDEX_DIR/artists.txt"
    sqlite3 "$db_file" "SELECT DISTINCT album FROM tracks ORDER BY album;" > "$INDEX_DIR/albums.txt"
    sqlite3 "$db_file" "SELECT DISTINCT title FROM tracks ORDER BY title;" > "$INDEX_DIR/titles.txt"

    # Create artist-album mapping
    sqlite3 "$db_file" "SELECT artist || '|' || album FROM tracks GROUP BY artist, album ORDER BY artist, album;" > "$INDEX_DIR/artist_albums.txt"

    success "Search indexes created"
}

# Function to create deduplication index
create_dedup_index() {
    log "Creating deduplication index..."

    local dedup_file="$INDEX_DIR/dedup_index.txt"

    # Create hash-based deduplication index
    find "$FLAT_SOURCE" -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.wav" -o -name "*.ogg" \) | while read -r file; do
        local hash=$(md5sum "$file" | cut -d' ' -f1)
        local relative_path="${file#$FLAT_SOURCE/}"
        echo "$hash|$relative_path" >> "$dedup_file"
    done

    # Sort and remove duplicates
    sort -u "$dedup_file" -o "$dedup_file"

    success "Deduplication index created with $(wc -l < "$dedup_file") entries"
}

# Function to update docker-compose configuration
update_docker_compose() {
    log "Updating docker-compose.yml to use organized library..."

    local compose_file="/home/th3tn/nextcloud-modern/docker-compose.yml"

    if [[ -f "$compose_file" ]]; then
        # Backup original
        cp "$compose_file" "$compose_file.backup-$(date +%Y%m%d-%H%M%S)"

        # Update paths to point to organized structure
        sed -i "s|/mnt/nvme/hot/stepheybot-music-org/organized:/music:ro|$ORGANIZED_TARGET:/music:ro|g" "$compose_file"

        success "Docker-compose configuration updated"
    else
        warn "Docker-compose file not found at $compose_file"
    fi
}

# Function to generate statistics
generate_final_stats() {
    log "Generating final statistics..."

    local stats_file="$INDEX_DIR/organization_stats.json"
    local db_file="$DATABASE_DIR/library.db"

    # Get database statistics
    local total_tracks=$(sqlite3 "$db_file" "SELECT COUNT(*) FROM tracks;")
    local total_artists=$(sqlite3 "$db_file" "SELECT COUNT(DISTINCT artist) FROM tracks;")
    local total_albums=$(sqlite3 "$db_file" "SELECT COUNT(DISTINCT artist || '|' || album) FROM tracks;")
    local total_size=$(sqlite3 "$db_file" "SELECT SUM(file_size) FROM tracks;")

    cat > "$stats_file" <<EOF
{
    "organization_method": "symlink",
    "total_files_processed": $TOTAL_FILES,
    "successfully_organized": $ORGANIZED_FILES,
    "failed_files": $FAILED_FILES,
    "artists_created": $ARTISTS_CREATED,
    "albums_created": $ALBUMS_CREATED,
    "database_stats": {
        "total_tracks": $total_tracks,
        "total_artists": $total_artists,
        "total_albums": $total_albums,
        "total_size_bytes": $total_size,
        "total_size_human": "$(numfmt --to=iec-i --suffix=B $total_size 2>/dev/null || echo "N/A")"
    },
    "paths": {
        "source": "$FLAT_SOURCE",
        "organized": "$ORGANIZED_TARGET",
        "database": "$DATABASE_DIR",
        "indexes": "$INDEX_DIR"
    },
    "completion_time": "$(date -Iseconds)",
    "success_rate": "$(echo "scale=2; $ORGANIZED_FILES * 100 / $TOTAL_FILES" | bc -l 2>/dev/null || echo "N/A")%"
}
EOF

    success "Statistics generated: $stats_file"

    # Display summary
    echo
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}           STEPHEYBOT MUSIC ORGANIZATION COMPLETE          ${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}📁 Total Files Processed:${NC} $TOTAL_FILES"
    echo -e "${GREEN}✅ Successfully Organized:${NC} $ORGANIZED_FILES"
    echo -e "${RED}❌ Failed Files:${NC} $FAILED_FILES"
    echo -e "${YELLOW}🎤 Artists Created:${NC} $ARTISTS_CREATED"
    echo -e "${YELLOW}💿 Albums Created:${NC} $ALBUMS_CREATED"
    echo -e "${CYAN}📊 Database Tracks:${NC} $total_tracks"
    echo -e "${CYAN}🎭 Database Artists:${NC} $total_artists"
    echo -e "${CYAN}📀 Database Albums:${NC} $total_albums"
    echo -e "${CYAN}💾 Total Size:${NC} $(numfmt --to=iec-i --suffix=B $total_size 2>/dev/null || echo "N/A")"
    echo -e "${CYAN}🔗 Organization Method:${NC} Symlinks (no duplication)"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════${NC}"
    echo
}

# Function to setup post-organization services
setup_services() {
    log "Setting up post-organization services..."

    # Create cache management script
    cat > "$NVME_CACHE/manage_cache.sh" <<'CACHE_SCRIPT'
#!/bin/bash
# Smart cache management for organized library

CACHE_DIR="/mnt/nvme/hot/stepheybot-music-cache"
LIBRARY_DIR="/mnt/hdd/media/music/library"
MAX_CACHE_SIZE_GB=20

# Function to pre-cache popular artists
precache_popular() {
    local db_file="/mnt/hdd/media/music/databases/library.db"

    # Get top 10 artists by track count
    sqlite3 "$db_file" "SELECT name FROM artists ORDER BY track_count DESC LIMIT 10;" | while read -r artist; do
        find "$LIBRARY_DIR/$artist" -type l -name "*.mp3" | head -5 | while read -r symlink; do
            local target=$(readlink "$symlink")
            local cache_path="$CACHE_DIR/popular/${symlink#$LIBRARY_DIR/}"

            mkdir -p "$(dirname "$cache_path")"
            if [[ ! -f "$cache_path" ]] && [[ -f "$target" ]]; then
                cp "$target" "$cache_path"
                echo "Cached popular track: $(basename "$target")"
            fi
        done
    done
}

# Function to clean old cache
cleanup_cache() {
    local current_size=$(du -sb "$CACHE_DIR" 2>/dev/null | cut -f1 | awk '{print int($1/1024/1024/1024)}')

    if [[ $current_size -gt $MAX_CACHE_SIZE_GB ]]; then
        echo "Cache size ($current_size GB) exceeds limit. Cleaning..."
        find "$CACHE_DIR" -type f -name "*.mp3" -mtime +7 -delete
    fi
}

# Run cache management
precache_popular
cleanup_cache
CACHE_SCRIPT

    chmod +x "$NVME_CACHE/manage_cache.sh"

    success "Cache management script created"
}

# Main function
main() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║            STEPHEYBOT MUSIC QUICK ORGANIZATION              ║"
    echo "║                    Symlink-Based Solution                   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Validate source directory
    if [[ ! -d "$FLAT_SOURCE" ]]; then
        error "Source directory not found: $FLAT_SOURCE"
        exit 1
    fi

    # Count source files
    TOTAL_FILES=$(find "$FLAT_SOURCE" -maxdepth 1 -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.wav" -o -name "*.ogg" \) | wc -l)
    log "Found $TOTAL_FILES music files to organize"

    # Clean existing organized directory
    if [[ -d "$ORGANIZED_TARGET" ]]; then
        log "Backing up existing organized directory..."
        mv "$ORGANIZED_TARGET" "${ORGANIZED_TARGET}-backup-$(date +%Y%m%d-%H%M%S)"
    fi

    mkdir -p "$ORGANIZED_TARGET"

    log "Starting symlink-based organization..."

    # Process all music files
    local processed=0
    find "$FLAT_SOURCE" -maxdepth 1 -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.wav" -o -name "*.ogg" \) | while read -r file; do
        if create_organized_symlink "$file"; then
            ((processed++))

            # Progress indicator
            if (( processed % 100 == 0 )); then
                info "Processed $processed files..."
            fi
        fi
    done

    # Wait for background processing to complete
    wait

    log "Organization phase complete. Creating database and indexes..."

    # Set up database and indexes
    create_library_database
    populate_database
    create_search_indexes
    create_dedup_index

    # Set up additional services
    setup_services
    update_docker_compose

    # Generate final statistics
    generate_final_stats

    success "Quick organization complete!"

    # Next steps
    echo
    echo -e "${YELLOW}🔧 NEXT STEPS:${NC}"
    echo "1. Restart services: docker-compose restart navidrome stepheybot-music"
    echo "2. Trigger library scan: curl -X POST http://localhost:8083/api/v1/library/scan"
    echo "3. Test search: curl 'http://localhost:8083/api/v1/search/local/ABBA'"
    echo "4. Run cache preload: $NVME_CACHE/manage_cache.sh"
    echo "5. Verify organization: ls -la '$ORGANIZED_TARGET'"
    echo
    echo -e "${GREEN}✨ Your library is now organized with ZERO file duplication!${NC}"
    echo -e "${CYAN}💡 All files are symlinks pointing to the original flat structure${NC}"
    echo -e "${CYAN}🚀 This provides organized access while maintaining storage efficiency${NC}"
}

# Run main function
main "$@"
