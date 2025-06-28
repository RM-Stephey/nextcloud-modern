#!/bin/bash

# StepheyBot Music Ecosystem Optimizer
# Creates comprehensive databases, indexes, and optimizations for professional music library
# Usage: ./optimize-music-ecosystem.sh [--skip-db] [--skip-index] [--force]

set -euo pipefail

# Neon color theme for StepheyBot
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
PINK='\033[1;95m'
MAGENTA='\033[1;96m'
WHITE='\033[1;97m'
NC='\033[0m'

# Configuration
NVME_ORGANIZED="/mnt/nvme/hot/stepheybot-music-org/organized"
HDD_LIBRARY="/mnt/hdd/media/music/library"
DB_CACHE_DIR="/mnt/nvme/db-cache/music"
DATABASES_DIR="/mnt/hdd/media/music/databases"
INDEXES_DIR="/mnt/hdd/media/music/indexes"
METADATA_CACHE="/mnt/nvme/hot/metadata-cache"
LOG_FILE="/tmp/music-ecosystem-optimization-$(date +%Y%m%d-%H%M%S).log"

# Flags
SKIP_DB=false
SKIP_INDEX=false
FORCE=false

# Neon-themed output functions
print_neon_header() {
    echo -e "${PINK}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PINK}║${CYAN}              🎵 StepheyBot Music Ecosystem Optimizer 🎵              ${PINK}║${NC}"
    echo -e "${PINK}║${MAGENTA}           Professional Database & Performance Optimization          ${PINK}║${NC}"
    echo -e "${PINK}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_status() {
    echo -e "${CYAN}[EcoSystem]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_neon() {
    echo -e "${PINK}[NEON]${NC} $1" | tee -a "$LOG_FILE"
}

print_db() {
    echo -e "${PURPLE}[DATABASE]${NC} $1" | tee -a "$LOG_FILE"
}

print_perf() {
    echo -e "${MAGENTA}[PERFORMANCE]${NC} $1" | tee -a "$LOG_FILE"
}

# Parse arguments
for arg in "$@"; do
    case $arg in
        --skip-db)
            SKIP_DB=true
            shift
            ;;
        --skip-index)
            SKIP_INDEX=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "StepheyBot Music Ecosystem Optimizer"
            echo "Usage: $0 [--skip-db] [--skip-index] [--force]"
            echo ""
            echo "Comprehensive optimization strategy:"
            echo "  1. SQLite database for ultra-fast lookups"
            echo "  2. Full-text search indexes"
            echo "  3. Metadata caching on NVME"
            echo "  4. API performance optimization"
            echo "  5. Navidrome integration preparation"
            echo "  6. Monitoring and health checks"
            exit 0
            ;;
        *)
            print_error "Unknown option: $arg"
            exit 1
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    print_status "🔍 Checking optimization prerequisites..."

    # Check if organized library exists
    if [[ ! -d "$NVME_ORGANIZED" ]]; then
        print_error "❌ Organized library not found: $NVME_ORGANIZED"
        exit 1
    fi

    # Check available tools
    local missing_tools=()

    if ! command -v sqlite3 &> /dev/null; then
        missing_tools+=("sqlite3")
    fi

    if ! command -v ffprobe &> /dev/null; then
        missing_tools+=("ffmpeg")
    fi

    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "❌ Missing required tools: ${missing_tools[*]}"
        print_info "Install with: sudo pacman -S sqlite ffmpeg jq"
        exit 1
    fi

    # Check storage space
    local nvme_available=$(df -B1 /mnt/nvme/db-cache | awk 'NR==2 {print $4}')
    local hdd_available=$(df -B1 /mnt/hdd/media | awk 'NR==2 {print $4}')

    print_success "✅ Prerequisites verified"
    print_perf "💾 NVME cache available: $(numfmt --to=iec $nvme_available)"
    print_perf "💾 HDD storage available: $(numfmt --to=iec $hdd_available)"
}

# Create directory structure
create_directory_structure() {
    print_status "📁 Creating optimization directory structure..."

    mkdir -p "$DB_CACHE_DIR"
    mkdir -p "$DATABASES_DIR"
    mkdir -p "$INDEXES_DIR"
    mkdir -p "$METADATA_CACHE"

    # Create database structure
    mkdir -p "$DATABASES_DIR/sqlite"
    mkdir -p "$DATABASES_DIR/cache"
    mkdir -p "$DATABASES_DIR/backups"

    # Create index structure
    mkdir -p "$INDEXES_DIR/search"
    mkdir -p "$INDEXES_DIR/genre"
    mkdir -p "$INDEXES_DIR/artist"
    mkdir -p "$INDEXES_DIR/album"

    print_success "✅ Directory structure created"
}

# Extract comprehensive metadata
extract_metadata() {
    print_status "🎵 Extracting comprehensive metadata from organized library..."

    local metadata_file="$METADATA_CACHE/complete_metadata.json"
    local temp_file="$METADATA_CACHE/temp_metadata.json"

    print_info "📊 Processing 1447 files for metadata extraction..."

    # Initialize JSON array
    echo "[]" > "$temp_file"

    local processed=0
    while IFS= read -r -d '' file; do
        local rel_path="${file#$NVME_ORGANIZED/}"
        local filename=$(basename "$file")
        local dir_path=$(dirname "$rel_path")
        local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)

        # Extract audio metadata using ffprobe
        local ffprobe_output
        ffprobe_output=$(ffprobe -v quiet -print_format json -show_format -show_streams "$file" 2>/dev/null || echo '{}')

        # Parse artist/album from directory structure
        local artist=""
        local album=""
        if [[ "$dir_path" =~ ^([^/]+)/(.+)$ ]]; then
            artist="${BASH_REMATCH[1]}"
            album="${BASH_REMATCH[2]}"
        elif [[ "$dir_path" =~ ^_([^/]+)/(.+)$ ]]; then
            artist="Various Artists"
            album="${BASH_REMATCH[2]}"
        fi

        # Create comprehensive metadata object
        local metadata=$(cat << EOF
{
    "id": "$processed",
    "file_path": "$rel_path",
    "filename": "$filename",
    "directory": "$dir_path",
    "artist": "$artist",
    "album": "$album",
    "file_size": $file_size,
    "file_extension": "${filename##*.}",
    "last_modified": $(stat -f%m "$file" 2>/dev/null || stat -c%Y "$file" 2>/dev/null),
    "audio_metadata": $ffprobe_output,
    "indexed_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)

        # Add to JSON array
        jq ". += [$metadata]" "$temp_file" > "$temp_file.tmp" && mv "$temp_file.tmp" "$temp_file"

        ((processed++))
        if (( processed % 100 == 0 )); then
            print_info "   📊 Processed $processed/1447 files..."
        fi
    done < <(find "$NVME_ORGANIZED" -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" \) -print0)

    mv "$temp_file" "$metadata_file"

    print_success "✅ Metadata extraction completed: $processed files"
    print_db "📊 Metadata file: $metadata_file"
}

# Create SQLite database
create_sqlite_database() {
    if [[ "$SKIP_DB" == true ]]; then
        print_warning "⏭️  Skipping database creation"
        return
    fi

    print_status "🗄️  Creating SQLite database for ultra-fast queries..."

    local db_file="$DATABASES_DIR/sqlite/stepheybot_music.db"
    local cache_db="$DB_CACHE_DIR/stepheybot_music_cache.db"

    # Create main database
    sqlite3 "$db_file" << 'EOF'
-- StepheyBot Music Library Database Schema
CREATE TABLE IF NOT EXISTS tracks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT UNIQUE NOT NULL,
    filename TEXT NOT NULL,
    directory TEXT NOT NULL,
    artist TEXT,
    album TEXT,
    title TEXT,
    track_number INTEGER,
    year INTEGER,
    genre TEXT,
    duration REAL,
    bitrate INTEGER,
    sample_rate INTEGER,
    file_size INTEGER,
    file_extension TEXT,
    last_modified INTEGER,
    date_added INTEGER DEFAULT (strftime('%s', 'now')),
    play_count INTEGER DEFAULT 0,
    last_played INTEGER,
    rating INTEGER DEFAULT 0,
    tags TEXT -- JSON array of tags
);

CREATE TABLE IF NOT EXISTS artists (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    normalized_name TEXT,
    track_count INTEGER DEFAULT 0,
    album_count INTEGER DEFAULT 0,
    total_duration REAL DEFAULT 0,
    first_seen INTEGER DEFAULT (strftime('%s', 'now')),
    last_updated INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE TABLE IF NOT EXISTS albums (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    artist_id INTEGER,
    year INTEGER,
    track_count INTEGER DEFAULT 0,
    total_duration REAL DEFAULT 0,
    directory_path TEXT,
    artwork_path TEXT,
    date_added INTEGER DEFAULT (strftime('%s', 'now')),
    FOREIGN KEY (artist_id) REFERENCES artists (id)
);

CREATE TABLE IF NOT EXISTS genres (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    track_count INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS playlists (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT,
    track_ids TEXT, -- JSON array of track IDs
    created_date INTEGER DEFAULT (strftime('%s', 'now')),
    last_modified INTEGER DEFAULT (strftime('%s', 'now')),
    play_count INTEGER DEFAULT 0
);

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist);
CREATE INDEX IF NOT EXISTS idx_tracks_album ON tracks(album);
CREATE INDEX IF NOT EXISTS idx_tracks_genre ON tracks(genre);
CREATE INDEX IF NOT EXISTS idx_tracks_year ON tracks(year);
CREATE INDEX IF NOT EXISTS idx_tracks_file_path ON tracks(file_path);
CREATE INDEX IF NOT EXISTS idx_tracks_filename ON tracks(filename);
CREATE INDEX IF NOT EXISTS idx_tracks_directory ON tracks(directory);
CREATE INDEX IF NOT EXISTS idx_tracks_last_modified ON tracks(last_modified);
CREATE INDEX IF NOT EXISTS idx_tracks_date_added ON tracks(date_added);
CREATE INDEX IF NOT EXISTS idx_tracks_play_count ON tracks(play_count);
CREATE INDEX IF NOT EXISTS idx_tracks_rating ON tracks(rating);

-- Full-text search indexes
CREATE VIRTUAL TABLE IF NOT EXISTS tracks_fts USING fts5(
    filename, artist, album, title, genre, directory,
    content='tracks',
    content_rowid='id'
);

-- FTS triggers
CREATE TRIGGER IF NOT EXISTS tracks_ai AFTER INSERT ON tracks BEGIN
    INSERT INTO tracks_fts(rowid, filename, artist, album, title, genre, directory)
    VALUES (new.id, new.filename, new.artist, new.album, new.title, new.genre, new.directory);
END;

CREATE TRIGGER IF NOT EXISTS tracks_ad AFTER DELETE ON tracks BEGIN
    INSERT INTO tracks_fts(tracks_fts, rowid, filename, artist, album, title, genre, directory)
    VALUES ('delete', old.id, old.filename, old.artist, old.album, old.title, old.genre, old.directory);
END;

CREATE TRIGGER IF NOT EXISTS tracks_au AFTER UPDATE ON tracks BEGIN
    INSERT INTO tracks_fts(tracks_fts, rowid, filename, artist, album, title, genre, directory)
    VALUES ('delete', old.id, old.filename, old.artist, old.album, old.title, old.genre, old.directory);
    INSERT INTO tracks_fts(rowid, filename, artist, album, title, genre, directory)
    VALUES (new.id, new.filename, new.artist, new.album, new.title, new.genre, new.directory);
END;

-- Views for common queries
CREATE VIEW IF NOT EXISTS v_track_details AS
SELECT
    t.*,
    a.name as artist_name,
    al.title as album_title,
    al.year as album_year
FROM tracks t
LEFT JOIN artists a ON t.artist = a.name
LEFT JOIN albums al ON t.album = al.title AND al.artist_id = a.id;

CREATE VIEW IF NOT EXISTS v_library_stats AS
SELECT
    COUNT(*) as total_tracks,
    COUNT(DISTINCT artist) as total_artists,
    COUNT(DISTINCT album) as total_albums,
    COUNT(DISTINCT genre) as total_genres,
    SUM(file_size) as total_size,
    SUM(duration) as total_duration,
    AVG(bitrate) as avg_bitrate
FROM tracks;

-- Create materialized view for API performance
CREATE TABLE IF NOT EXISTS api_cache_artists AS
SELECT
    artist,
    COUNT(*) as track_count,
    COUNT(DISTINCT album) as album_count,
    SUM(duration) as total_duration,
    MIN(year) as first_year,
    MAX(year) as last_year
FROM tracks
WHERE artist IS NOT NULL
GROUP BY artist;

CREATE TABLE IF NOT EXISTS api_cache_albums AS
SELECT
    artist,
    album,
    COUNT(*) as track_count,
    SUM(duration) as total_duration,
    MIN(year) as year,
    directory
FROM tracks
WHERE artist IS NOT NULL AND album IS NOT NULL
GROUP BY artist, album;

EOF

    # Copy database to NVME for ultra-fast access
    cp "$db_file" "$cache_db"

    print_success "✅ SQLite database created with advanced indexing"
    print_db "💾 Main database: $db_file"
    print_db "⚡ Cache database: $cache_db"
}

# Populate database with metadata
populate_database() {
    if [[ "$SKIP_DB" == true ]]; then
        return
    fi

    print_status "📊 Populating database with extracted metadata..."

    local db_file="$DATABASES_DIR/sqlite/stepheybot_music.db"
    local metadata_file="$METADATA_CACHE/complete_metadata.json"

    if [[ ! -f "$metadata_file" ]]; then
        print_error "❌ Metadata file not found: $metadata_file"
        return 1
    fi

    # Process metadata and insert into database
    local temp_sql="$METADATA_CACHE/insert_data.sql"

    print_info "🔄 Converting JSON metadata to SQL..."

    jq -r '.[] |
        "INSERT OR REPLACE INTO tracks (file_path, filename, directory, artist, album, file_size, file_extension, last_modified) VALUES (" +
        "\"" + .file_path + "\", " +
        "\"" + .filename + "\", " +
        "\"" + .directory + "\", " +
        "\"" + (.artist // "") + "\", " +
        "\"" + (.album // "") + "\", " +
        (.file_size | tostring) + ", " +
        "\"" + .file_extension + "\", " +
        (.last_modified | tostring) + ");"
    ' "$metadata_file" > "$temp_sql"

    print_info "🗄️  Executing bulk insert..."
    sqlite3 "$db_file" < "$temp_sql"

    # Update cache tables
    sqlite3 "$db_file" << 'EOF'
DELETE FROM api_cache_artists;
INSERT INTO api_cache_artists
SELECT
    artist,
    COUNT(*) as track_count,
    COUNT(DISTINCT album) as album_count,
    SUM(COALESCE(duration, 0)) as total_duration,
    MIN(year) as first_year,
    MAX(year) as last_year
FROM tracks
WHERE artist IS NOT NULL AND artist != ''
GROUP BY artist;

DELETE FROM api_cache_albums;
INSERT INTO api_cache_albums
SELECT
    artist,
    album,
    COUNT(*) as track_count,
    SUM(COALESCE(duration, 0)) as total_duration,
    MIN(year) as year,
    directory
FROM tracks
WHERE artist IS NOT NULL AND album IS NOT NULL AND artist != '' AND album != ''
GROUP BY artist, album;
EOF

    # Update NVME cache
    cp "$db_file" "$DB_CACHE_DIR/stepheybot_music_cache.db"

    # Get statistics
    local stats=$(sqlite3 "$db_file" "SELECT * FROM v_library_stats;")

    print_success "✅ Database populated successfully"
    print_db "📊 Library statistics updated"

    rm -f "$temp_sql"
}

# Create search indexes
create_search_indexes() {
    if [[ "$SKIP_INDEX" == true ]]; then
        print_warning "⏭️  Skipping index creation"
        return
    fi

    print_status "🔍 Creating advanced search indexes..."

    # Artist index
    print_info "👨‍🎤 Building artist index..."
    sqlite3 "$DATABASES_DIR/sqlite/stepheybot_music.db" \
        "SELECT DISTINCT artist FROM tracks WHERE artist IS NOT NULL AND artist != '';" \
        > "$INDEXES_DIR/artist/artists.txt"

    # Album index
    print_info "💿 Building album index..."
    sqlite3 "$DATABASES_DIR/sqlite/stepheybot_music.db" \
        "SELECT DISTINCT album FROM tracks WHERE album IS NOT NULL AND album != '';" \
        > "$INDEXES_DIR/album/albums.txt"

    # Genre index (if available)
    print_info "🎼 Building genre index..."
    sqlite3 "$DATABASES_DIR/sqlite/stepheybot_music.db" \
        "SELECT DISTINCT genre FROM tracks WHERE genre IS NOT NULL AND genre != '';" \
        > "$INDEXES_DIR/genre/genres.txt"

    # File extension index
    print_info "📁 Building file type index..."
    sqlite3 "$DATABASES_DIR/sqlite/stepheybot_music.db" \
        "SELECT file_extension, COUNT(*) FROM tracks GROUP BY file_extension;" \
        > "$INDEXES_DIR/search/file_types.txt"

    # Create search term frequency index
    print_info "🔤 Building search term frequency index..."
    sqlite3 "$DATABASES_DIR/sqlite/stepheybot_music.db" << 'EOF' > "$INDEXES_DIR/search/term_frequency.json"
.mode json
SELECT
    json_object(
        'artists', (SELECT COUNT(DISTINCT artist) FROM tracks WHERE artist IS NOT NULL),
        'albums', (SELECT COUNT(DISTINCT album) FROM tracks WHERE album IS NOT NULL),
        'total_tracks', (SELECT COUNT(*) FROM tracks),
        'file_types', json_group_array(json_object('type', file_extension, 'count', cnt))
    ) as search_index
FROM (
    SELECT file_extension, COUNT(*) as cnt
    FROM tracks
    GROUP BY file_extension
);
EOF

    print_success "✅ Search indexes created"
    print_perf "📊 Indexes available for ultra-fast lookups"
}

# Create API optimization layer
create_api_optimization() {
    print_status "🚀 Creating API optimization layer..."

    local api_dir="$DATABASES_DIR/api"
    mkdir -p "$api_dir"

    # Create pre-computed API responses
    print_info "📡 Pre-computing common API responses..."

    # Artists endpoint
    sqlite3 "$DATABASES_DIR/sqlite/stepheybot_music.db" << 'EOF' > "$api_dir/artists.json"
.mode json
SELECT json_object(
    'artists', json_group_array(
        json_object(
            'name', artist,
            'track_count', track_count,
            'album_count', album_count,
            'total_duration', total_duration
        )
    )
) FROM api_cache_artists ORDER BY artist;
EOF

    # Albums endpoint
    sqlite3 "$DATABASES_DIR/sqlite/stepheybot_music.db" << 'EOF' > "$api_dir/albums.json"
.mode json
SELECT json_object(
    'albums', json_group_array(
        json_object(
            'artist', artist,
            'album', album,
            'track_count', track_count,
            'total_duration', total_duration,
            'year', year
        )
    )
) FROM api_cache_albums ORDER BY artist, album;
EOF

    # Statistics endpoint
    sqlite3 "$DATABASES_DIR/sqlite/stepheybot_music.db" << 'EOF' > "$api_dir/stats.json"
.mode json
SELECT json_object(
    'total_tracks', total_tracks,
    'total_artists', total_artists,
    'total_albums', total_albums,
    'total_size_bytes', total_size,
    'total_duration_seconds', total_duration,
    'average_bitrate', avg_bitrate,
    'last_updated', strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
) FROM v_library_stats;
EOF

    # Create Redis-style cache keys for common queries
    print_info "⚡ Creating query cache..."
    mkdir -p "$api_dir/cache"

    # Most played tracks (placeholder)
    echo '{"tracks": [], "note": "Play counts will be populated by usage"}' > "$api_dir/cache/most_played.json"

    # Recent additions
    sqlite3 "$DATABASES_DIR/sqlite/stepheybot_music.db" << 'EOF' > "$api_dir/cache/recent_additions.json"
.mode json
SELECT json_object(
    'recent_tracks', json_group_array(
        json_object(
            'file_path', file_path,
            'artist', artist,
            'album', album,
            'filename', filename,
            'date_added', date_added
        )
    )
) FROM (
    SELECT * FROM tracks ORDER BY date_added DESC LIMIT 50
);
EOF

    print_success "✅ API optimization layer created"
    print_perf "🚀 Pre-computed responses ready for lightning-fast API"
}

# Create monitoring and health checks
create_monitoring() {
    print_status "📊 Setting up monitoring and health checks..."

    local monitoring_dir="$DATABASES_DIR/monitoring"
    mkdir -p "$monitoring_dir"

    # Create health check script
    cat > "$monitoring_dir/health_check.sh" << 'EOF'
#!/bin/bash
# StepheyBot Music Library Health Check

DB_FILE="/mnt/hdd/media/music/databases/sqlite/stepheybot_music.db"
CACHE_DB="/mnt/nvme/db-cache/stepheybot_music_cache.db"
LIBRARY_DIR="/mnt/hdd/media/music/library"

echo "StepheyBot Music Library Health Check - $(date)"
echo "================================================"

# Database integrity
echo "🗄️  Database integrity:"
sqlite3 "$DB_FILE" "PRAGMA integrity_check;" | head -1

# Cache sync status
echo "⚡ Cache sync status:"
if [[ -f "$CACHE_DB" ]]; then
    echo "   Cache database: ✅ Available"
else
    echo "   Cache database: ❌ Missing"
fi

# Library statistics
echo "📊 Library statistics:"
sqlite3 "$DB_FILE" "SELECT 'Tracks: ' || total_tracks || ', Artists: ' || total_artists || ', Albums: ' || total_albums FROM v_library_stats;"

# Disk usage
echo "💾 Storage usage:"
echo "   Library: $(du -sh "$LIBRARY_DIR" | cut -f1)"
echo "   Database: $(du -sh "$(dirname "$DB_FILE")" | cut -f1)"

# File system consistency
echo "🔍 File system consistency:"
EXPECTED_FILES=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tracks;")
ACTUAL_FILES=$(find "$LIBRARY_DIR" -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" \) | wc -l)

if [[ "$EXPECTED_FILES" -eq "$ACTUAL_FILES" ]]; then
    echo "   File count: ✅ Consistent ($ACTUAL_FILES files)"
else
    echo "   File count: ⚠️  Mismatch (DB: $EXPECTED_FILES, FS: $ACTUAL_FILES)"
fi

echo ""
echo "Health check completed at $(date)"
EOF

    chmod +x "$monitoring_dir/health_check.sh"

    # Create performance monitoring
    cat > "$monitoring_dir/performance_monitor.sh" << 'EOF'
#!/bin/bash
# StepheyBot Performance Monitor

LOG_FILE="/tmp/music_performance_$(date +%Y%m%d).log"
DB_FILE="/mnt/hdd/media/music/databases/sqlite/stepheybot_music.db"

echo "$(date): Performance monitoring started" >> "$LOG_FILE"

# Query performance tests
echo "Testing query performance..." >> "$LOG_FILE"

time sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tracks;" 2>&1 | grep real >> "$LOG_FILE"
time sqlite3 "$DB_FILE" "SELECT * FROM tracks WHERE artist LIKE '%Armin%' LIMIT 10;" 2>&1 | grep real >> "$LOG_FILE"
time sqlite3 "$DB_FILE" "SELECT * FROM tracks_fts WHERE tracks_fts MATCH 'electronic';" 2>&1 | grep real >> "$LOG_FILE"

echo "$(date): Performance monitoring completed" >> "$LOG_FILE"
EOF

    chmod +x "$monitoring_dir/performance_monitor.sh"

    print_success "✅ Monitoring and health checks configured"
    print_perf "📊 Health check: $monitoring_dir/health_check.sh"
}

# Create backup strategy
create_backup_strategy() {
    print_status "💾 Creating comprehensive backup strategy..."

    local backup_dir="$DATABASES_DIR/backups"
    mkdir -p "$backup_dir/daily"
    mkdir -p "$backup_dir/weekly"
    mkdir -p "$backup_dir/monthly"

    # Daily backup script
    cat > "$backup_dir/daily_backup.sh" << 'EOF'
#!/bin/bash
# StepheyBot Daily Database Backup

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_FILE="/mnt/hdd/media/music/databases/sqlite/stepheybot_music.db"
BACKUP_DIR="/mnt/hdd/media/music/databases/backups/daily"
METADATA_DIR="/mnt/nvme/hot/metadata-cache"

# Backup database
cp "$DB_FILE" "$BACKUP_DIR/stepheybot_music_$TIMESTAMP.db"

# Backup metadata cache
tar -czf "$BACKUP_DIR/metadata_cache_$TIMESTAMP.tar.gz" -C "$METADATA_DIR" .

# Keep only last 7 days of daily backups
find "$BACKUP_DIR" -name "stepheybot_music_*.db" -mtime +7 -delete
find "$BACKUP_DIR" -name "metadata_cache_*.tar.gz" -mtime +7 -delete

echo "Daily backup completed: $TIMESTAMP"
EOF

    chmod +x "$backup_dir/daily_backup.sh"

    # Create initial backup
    "$backup_dir/daily_backup.sh"

    print_success "✅ Backup strategy implemented"
    print_db "💾 Daily backups configured"
}

# Generate optimization report
generate_report() {
    print_status "📋 Generating optimization report..."

    local report_file="$DATABASES_DIR/optimization_report_$(date +%Y%m%d_%H%M%S).txt"

    cat > "$report_file" << EOF
╔════════════════════════════════════════════════════════════════════╗
║              🎵 StepheyBot Music Ecosystem Optimization Report      ║
║                           $(date)                        ║
╚════════════════════════════════════════════════════════════════════╝

🎯 OPTIMIZATION SUMMARY:
=======================
✅ SQLite database created with advanced indexing
✅ Full-text search capabilities implemented
✅ API optimization layer with pre-computed responses
✅ Metadata extraction and caching on NVME
✅ Performance monitoring and health checks
✅ Comprehensive backup strategy

📊 LIBRARY STATISTICS:
=====================
$(sqlite3 "$DATABASES_DIR/sqlite/stepheybot_music.db" "SELECT '📁 Total Tracks: ' || total_tracks || char(10) || '🎤 Total Artists: ' || total_artists || char(10) || '💿 Total Albums: ' || total_albums FROM v_library_stats;")

🔧 OPTIMIZATION COMPONENTS:
==========================
📁 Database: $DATABASES_DIR/sqlite/stepheybot_music.db
⚡ NVME Cache: $DB_CACHE_DIR/stepheybot_music_cache.db
📊 Indexes: $INDEXES_DIR/
🚀 API Cache: $DATABASES_DIR/api/
📋 Monitoring: $DATABASES_DIR/monitoring/
💾 Backups: $DATABASES_DIR/backups/

🎵 StepheyBot Music Ecosystem Optimization Complete! 🎵
EOF

    print_success "✅ Optimization report generated: $report_file"
}

# Main execution
main() {
    print_neon_header

    print_neon "🎵 COMPREHENSIVE MUSIC ECOSYSTEM OPTIMIZATION 🎵"
    print_info "Creating professional-grade database and performance layer"
    print_info "Log file: $LOG_FILE"

    # Execute optimization steps
    check_prerequisites
    create_directory_structure
    extract_metadata
    create_sqlite_database
    populate_database
    create_search_indexes
    create_api_optimization
    create_monitoring
    create_backup_strategy
    generate_report

    print_neon "🎉 MUSIC ECOSYSTEM OPTIMIZATION COMPLETE! 🎉"
    print_success "Your music library is now professionally optimized"
}

# Execute main function
main "$@"
