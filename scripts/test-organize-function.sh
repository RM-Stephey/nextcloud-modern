#!/bin/bash

# StepheyBot Music - Test Organize Function
# Debug script to test file organization function in isolation

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
FLAT_SOURCE="/mnt/hdd/media/music/library-flat-backup"
ORGANIZED_TARGET="/tmp/test_organize"
INDEX_DIR="/tmp/test_organize/indexes"

# Statistics
ORGANIZED_FILES=0
FAILED_FILES=0
ARTISTS_CREATED=0
ALBUMS_CREATED=0

# Create test directories
mkdir -p "$ORGANIZED_TARGET" "$INDEX_DIR"

# Logging functions
log() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
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

# Function to calculate file hash
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

    log "Processing file $index/$total: $filename"

    # Skip non-music files
    if [[ ! "$filename" =~ \.(mp3|flac|m4a|wav|ogg|wma|aac)$ ]]; then
        log "Skipping non-music file: $filename"
        return 0
    fi

    # Check file size (skip if too small - likely corrupted)
    local file_size=$(stat -c%s "$source_file" 2>/dev/null || echo 0)
    if [[ $file_size -lt 1000 ]]; then
        log "Skipping tiny file (likely corrupted): $filename"
        return 0
    fi

    log "File size: $file_size bytes"

    # Parse filename
    local metadata=$(parse_filename "$filename")
    local artist=$(echo "$metadata" | cut -d'|' -f1)
    local title=$(echo "$metadata" | cut -d'|' -f2)

    log "Parsed - Artist: '$artist', Title: '$title'"

    # Determine album
    local album=$(determine_album "$artist" "$title" "$filename")
    log "Determined album: '$album'"

    # Sanitize for filesystem
    local safe_artist=$(sanitize_filename "$artist")
    local safe_album=$(sanitize_filename "$album")
    local safe_title=$(sanitize_filename "$title")

    log "Sanitized - Artist: '$safe_artist', Album: '$safe_album', Title: '$safe_title'"

    # Create target directory structure
    local artist_dir="$ORGANIZED_TARGET/$safe_artist"
    local album_dir="$artist_dir/$safe_album"

    log "Creating directories: $album_dir"

    # Create directories if they don't exist
    if [[ ! -d "$artist_dir" ]]; then
        mkdir -p "$artist_dir"
        ((ARTISTS_CREATED++))
        log "Created artist directory: $safe_artist"
    fi

    if [[ ! -d "$album_dir" ]]; then
        mkdir -p "$album_dir"
        ((ALBUMS_CREATED++))
        log "Created album directory: $safe_album"
    fi

    # Determine target filename
    local extension="${filename##*.}"
    local target_file="$album_dir/$safe_title.$extension"

    log "Target file: $target_file"

    # Handle duplicates
    local counter=1
    while [[ -f "$target_file" ]]; do
        local existing_hash=$(calculate_hash "$target_file")
        local new_hash=$(calculate_hash "$source_file")

        if [[ "$existing_hash" == "$new_hash" ]]; then
            log "Duplicate found (same content): $filename -> skipping"
            return 0
        else
            target_file="$album_dir/$safe_title ($counter).$extension"
            ((counter++))
            log "Duplicate name, trying: $target_file"
        fi
    done

    # Copy file (preserve metadata and timestamps)
    log "Copying file: $source_file -> $target_file"
    if cp -p "$source_file" "$target_file"; then
        ((ORGANIZED_FILES++))

        # Add to index for database population
        echo "$target_file|$artist|$album|$title|$(date +%s)|$file_size|$(calculate_hash "$target_file")" >> "$INDEX_DIR/organized_files.txt"

        success "Successfully organized: $filename -> $safe_artist/$safe_album/"
        return 0
    else
        error "Failed to copy: $filename"
        ((FAILED_FILES++))
        return 1
    fi
}

# Test function
test_organize() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    ORGANIZE FUNCTION TEST                   ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

    # Initialize index file
    echo "# Test organized files index" > "$INDEX_DIR/organized_files.txt"

    # Test with first few files from the source
    local test_files=(
        "ABBA - Dancing Queen.mp3"
        "Armin van Buuren - Intense.mp3"
        "Above & Beyond - Blue Monday - Extended Mix.mp3"
    )

    local file_index=0
    for test_file in "${test_files[@]}"; do
        ((file_index++))
        local full_path="$FLAT_SOURCE/$test_file"

        echo
        log "=== Testing file $file_index: $test_file ==="

        if [[ -f "$full_path" ]]; then
            organize_file "$full_path" "$file_index" "${#test_files[@]}"
        else
            error "Test file not found: $full_path"
            # Try to find a similar file
            local found_file=$(find "$FLAT_SOURCE" -maxdepth 1 -name "*ABBA*" -o -name "*Armin*" -o -name "*Above*" | head -1)
            if [[ -n "$found_file" ]]; then
                log "Using alternate file: $(basename "$found_file")"
                organize_file "$found_file" "$file_index" "${#test_files[@]}"
            fi
        fi
    done

    echo
    echo -e "${CYAN}=== TEST RESULTS ===${NC}"
    echo "Organized files: $ORGANIZED_FILES"
    echo "Failed files: $FAILED_FILES"
    echo "Artists created: $ARTISTS_CREATED"
    echo "Albums created: $ALBUMS_CREATED"

    echo
    echo -e "${CYAN}=== DIRECTORY STRUCTURE ===${NC}"
    find "$ORGANIZED_TARGET" -type f | head -10

    echo
    echo -e "${CYAN}=== INDEX FILE ===${NC}"
    cat "$INDEX_DIR/organized_files.txt"
}

# Run the test
test_organize
