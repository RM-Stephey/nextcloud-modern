#!/bin/bash

# StepheyBot Music - Quick Fix Organization Script
# Simplified version that avoids subshell issues

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Configuration
FLAT_SOURCE="/mnt/hdd/media/music/library-flat-backup"
ORGANIZED_TARGET="/mnt/hdd/media/music/library"
DATABASE_DIR="/mnt/hdd/media/music/databases"
INDEX_DIR="/mnt/hdd/media/music/indexes"
LOG_FILE="/mnt/hdd/media/music/quick-organization.log"

# Statistics
TOTAL_FILES=0
PROCESSED_FILES=0
ORGANIZED_FILES=0
FAILED_FILES=0
ARTISTS_CREATED=0
ALBUMS_CREATED=0
START_TIME=$(date +%s)

# Create directories
mkdir -p "$ORGANIZED_TARGET" "$DATABASE_DIR" "$INDEX_DIR"

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

progress() {
    echo -e "${WHITE}[PROGRESS]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Sanitize filename
sanitize_filename() {
    echo "$1" | sed 's/[<>:"/\\|?*]/_/g' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Parse filename for artist and title
parse_filename() {
    local filename="$1"
    local basename="${filename%.*}"

    # Remove track numbers
    basename=$(echo "$basename" | sed 's/^[0-9]\+[[:space:]]*-[[:space:]]*//')

    if [[ "$basename" =~ ^(.+)[[:space:]]*-[[:space:]]*(.+)$ ]]; then
        local artist="${BASH_REMATCH[1]}"
        local title="${BASH_REMATCH[2]}"

        # Clean up artist (handle collaborations)
        if [[ "$artist" =~ ^(.+)[[:space:]]*,[[:space:]]*(.+)$ ]]; then
            artist="${BASH_REMATCH[1]}"
        fi

        echo "$artist|$title"
    else
        echo "Unknown Artist|$basename"
    fi
}

# Determine album category
determine_album() {
    local title="$2"
    local filename="$3"

    if [[ "$title" =~ [Rr]emix|[Mm]ix|[Ee]dit|[Rr]ework ]]; then
        echo "Remixes & Edits"
    elif [[ "$title" =~ [Ll]ive|[Aa]coustic ]]; then
        echo "Live & Acoustic"
    elif [[ "$filename" =~ [Cc]ompilation|[Cc]ollection ]]; then
        echo "Compilations"
    else
        echo "Singles"
    fi
}

# Organize a single file
organize_file() {
    local source_file="$1"
    local filename=$(basename "$source_file")

    # Skip non-music files
    if [[ ! "$filename" =~ \.(mp3|flac|m4a|wav|ogg)$ ]]; then
        return 0
    fi

    # Parse filename
    local metadata=$(parse_filename "$filename")
    local artist=$(echo "$metadata" | cut -d'|' -f1)
    local title=$(echo "$metadata" | cut -d'|' -f2)
    local album=$(determine_album "$artist" "$title" "$filename")

    # Sanitize names
    local safe_artist=$(sanitize_filename "$artist")
    local safe_album=$(sanitize_filename "$album")
    local safe_title=$(sanitize_filename "$title")

    # Create directory structure
    local artist_dir="$ORGANIZED_TARGET/$safe_artist"
    local album_dir="$artist_dir/$safe_album"

    if [[ ! -d "$artist_dir" ]]; then
        mkdir -p "$artist_dir"
        ((ARTISTS_CREATED++))
    fi

    if [[ ! -d "$album_dir" ]]; then
        mkdir -p "$album_dir"
        ((ALBUMS_CREATED++))
    fi

    # Create target file path
    local extension="${filename##*.}"
    local target_file="$album_dir/$safe_title.$extension"

    # Handle duplicates with counter
    local counter=1
    while [[ -f "$target_file" ]]; do
        target_file="$album_dir/$safe_title ($counter).$extension"
        ((counter++))
    done

    # Copy file
    if cp -p "$source_file" "$target_file"; then
        ((ORGANIZED_FILES++))

        # Add to index
        local file_size=$(stat -c%s "$target_file" 2>/dev/null || echo 0)
        echo "$target_file|$artist|$album|$title|$(date +%s)|$file_size" >> "$INDEX_DIR/organized_index.txt"

        return 0
    else
        ((FAILED_FILES++))
        return 1
    fi
}

# Create database
create_database() {
    log "Creating library database..."

    local db_file="$DATABASE_DIR/library.db"
    rm -f "$db_file"

    sqlite3 "$db_file" <<'EOF'
CREATE TABLE tracks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT UNIQUE NOT NULL,
    artist TEXT NOT NULL,
    album TEXT NOT NULL,
    title TEXT NOT NULL,
    file_size INTEGER,
    date_added INTEGER
);

CREATE INDEX idx_artist ON tracks(artist);
CREATE INDEX idx_album ON tracks(album);
CREATE INDEX idx_title ON tracks(title);

CREATE VIRTUAL TABLE tracks_fts USING fts5(
    artist, album, title,
    content='tracks',
    content_rowid='id'
);

CREATE TABLE library_stats (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    total_tracks INTEGER DEFAULT 0,
    total_artists INTEGER DEFAULT 0,
    total_albums INTEGER DEFAULT 0,
    last_updated INTEGER
);

INSERT INTO library_stats (id, last_updated) VALUES (1, strftime('%s', 'now'));
EOF

    success "Database created"
}

# Populate database
populate_database() {
    log "Populating database..."

    local db_file="$DATABASE_DIR/library.db"
    local index_file="$INDEX_DIR/organized_index.txt"

    if [[ ! -f "$index_file" ]]; then
        error "No organized index found"
        return 1
    fi

    local temp_sql="/tmp/populate.sql"
    echo "BEGIN TRANSACTION;" > "$temp_sql"

    while IFS='|' read -r file_path artist album title date_added file_size; do
        # Escape quotes
        artist=$(echo "$artist" | sed "s/'/''/g")
        album=$(echo "$album" | sed "s/'/''/g")
        title=$(echo "$title" | sed "s/'/''/g")
        file_path=$(echo "$file_path" | sed "s/'/''/g")

        echo "INSERT INTO tracks (file_path, artist, album, title, file_size, date_added) VALUES ('$file_path', '$artist', '$album', '$title', $file_size, $date_added);" >> "$temp_sql"
    done < "$index_file"

    echo "INSERT INTO tracks_fts(rowid, artist, album, title) SELECT id, artist, album, title FROM tracks;" >> "$temp_sql"
    echo "UPDATE library_stats SET total_tracks = (SELECT COUNT(*) FROM tracks), total_artists = (SELECT COUNT(DISTINCT artist) FROM tracks), total_albums = (SELECT COUNT(DISTINCT artist || '|' || album) FROM tracks), last_updated = strftime('%s', 'now') WHERE id = 1;" >> "$temp_sql"
    echo "COMMIT;" >> "$temp_sql"

    sqlite3 "$db_file" < "$temp_sql"
    rm -f "$temp_sql"

    success "Database populated"
}

# Main function
main() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              STEPHEYBOT MUSIC QUICK ORGANIZATION            ║"
    echo "║                     Fixed Version v2.0                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Check source directory
    if [[ ! -d "$FLAT_SOURCE" ]]; then
        error "Source directory not found: $FLAT_SOURCE"
        exit 1
    fi

    # Count files using array to avoid subshell issues
    log "Scanning for music files..."
    mapfile -t music_files < <(find "$FLAT_SOURCE" -maxdepth 1 -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.wav" -o -name "*.ogg" \))
    TOTAL_FILES=${#music_files[@]}

    if [[ $TOTAL_FILES -eq 0 ]]; then
        error "No music files found"
        exit 1
    fi

    success "Found $TOTAL_FILES music files to organize"

    # Confirm operation
    echo
    read -p "Continue with organization? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Operation cancelled"
        exit 0
    fi

    # Backup existing library
    if [[ -d "$ORGANIZED_TARGET" ]]; then
        log "Backing up existing library..."
        mv "$ORGANIZED_TARGET" "${ORGANIZED_TARGET}-backup-$(date +%Y%m%d-%H%M%S)"
    fi

    mkdir -p "$ORGANIZED_TARGET"

    # Initialize index
    echo "# Organized files index" > "$INDEX_DIR/organized_index.txt"

    log "Starting file organization..."

    # Process files using for loop to avoid subshell issues
    for source_file in "${music_files[@]}"; do
        ((PROCESSED_FILES++))

        # Show progress every 50 files
        if (( PROCESSED_FILES % 50 == 0 )); then
            local percentage=$((PROCESSED_FILES * 100 / TOTAL_FILES))
            progress "[$PROCESSED_FILES/$TOTAL_FILES] ${percentage}% - Processing: $(basename "$source_file")"
        fi

        organize_file "$source_file"
    done

    log "File organization complete"

    # Create database
    create_database
    populate_database

    # Calculate final stats
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local success_rate=0
    if [[ $TOTAL_FILES -gt 0 ]]; then
        success_rate=$((ORGANIZED_FILES * 100 / TOTAL_FILES))
    fi

    # Display results
    echo
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                    ORGANIZATION COMPLETE                    ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${CYAN}📊 RESULTS:${NC}"
    echo -e "   📁 Total Files: ${WHITE}$TOTAL_FILES${NC}"
    echo -e "   ✅ Organized: ${GREEN}$ORGANIZED_FILES${NC}"
    echo -e "   ❌ Failed: ${RED}$FAILED_FILES${NC}"
    echo -e "   🎤 Artists: ${WHITE}$ARTISTS_CREATED${NC}"
    echo -e "   💿 Albums: ${WHITE}$ALBUMS_CREATED${NC}"
    echo -e "   📈 Success Rate: ${GREEN}${success_rate}%${NC}"
    echo -e "   ⏱️  Duration: ${WHITE}${duration}s${NC}"
    echo
    echo -e "${YELLOW}🔧 NEXT STEPS:${NC}"
    echo "1. docker-compose restart navidrome stepheybot-music"
    echo "2. curl -X POST http://localhost:8083/api/v1/library/scan"
    echo "3. Test: ls -la '$ORGANIZED_TARGET'"
    echo
    echo -e "${GREEN}✨ Library organization complete!${NC}"

    success "Organization completed successfully"
}

# Cleanup on interrupt
cleanup() {
    echo
    error "Interrupted - cleaning up..."
    rm -f "/tmp/populate.sql"
    exit 1
}

trap cleanup SIGINT SIGTERM

# Run main function
main "$@"
