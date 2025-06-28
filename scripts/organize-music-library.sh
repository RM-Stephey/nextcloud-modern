#!/bin/bash

# StepheyBot Music Library Organizer
# Transforms flat music library into proper Artist/Album structure for music.stepheybot.dev
# Usage: ./organize-music-library.sh [--dry-run] [--force] [--skip-backup]

set -euo pipefail

# Colors for neon-themed output (Stephey's preference!)
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
PINK='\033[1;95m'
NC='\033[0m' # No Color

# Configuration
MUSIC_LIBRARY="/mnt/hdd/media/music/library"
ORGANIZED_LIBRARY="/mnt/hdd/media/music/organized"
BACKUP_DIR="/mnt/hdd/media/music/backups/pre-organization-$(date +%Y%m%d-%H%M%S)"
BEETS_CONFIG="/tmp/stepheybot-beets-config.yaml"
LOG_FILE="/tmp/music-organization-$(date +%Y%m%d-%H%M%S).log"

# Flags
DRY_RUN=false
FORCE=false
SKIP_BACKUP=false

# Function to print neon-themed output
print_neon_header() {
    echo -e "${PINK}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PINK}║${CYAN}                    🎵 StepheyBot Music Organizer 🎵             ${PINK}║${NC}"
    echo -e "${PINK}║${BLUE}                   Transform Your Music Library                  ${PINK}║${NC}"
    echo -e "${PINK}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_status() {
    echo -e "${BLUE}[StepheyBot]${NC} $1" | tee -a "$LOG_FILE"
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
    echo -e "${CYAN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_neon() {
    echo -e "${PINK}[NEON]${NC} $1" | tee -a "$LOG_FILE"
}

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        -h|--help)
            echo "StepheyBot Music Library Organizer"
            echo "Usage: $0 [--dry-run] [--force] [--skip-backup]"
            echo ""
            echo "Options:"
            echo "  --dry-run      Show what would be done without making changes"
            echo "  --force        Skip confirmation prompts"
            echo "  --skip-backup  Skip creating backup (not recommended)"
            echo "  --help         Show this help message"
            echo ""
            echo "This script organizes your flat music library into Artist/Album structure"
            echo "for optimal performance with music.stepheybot.dev"
            exit 0
            ;;
        *)
            print_error "Unknown option: $arg"
            exit 1
            ;;
    esac
done

# Create beets configuration
create_beets_config() {
    print_status "📝 Creating beets configuration..."

    cat > "$BEETS_CONFIG" << 'EOF'
# StepheyBot Music System - Beets Configuration for Library Organization
directory: /mnt/hdd/media/music/organized
library: /tmp/stepheybot-organization.db

# Import settings for organization
import:
    write: yes
    copy: yes
    move: no
    resume: yes
    incremental: no
    quiet_fallback: skip
    timid: no
    log: /tmp/beets-import.log
    duplicate_action: skip
    bell: no

# Path formatting - StepheyBot preferred structure
paths:
    default: $albumartist/$album%aunique{}/$track - $title
    singleton: _Singles/$artist/$title
    comp: _Compilations/$album%aunique{}/$track - $title
    albumtype:soundtrack: _Soundtracks/$album/$track - $title
    albumtype:compilation: _Compilations/$album%aunique{}/$track - $title

# Character replacement for filesystem compatibility
replace:
    '[\\/]': _
    '^\.': _
    '[\x00-\x1f]': _
    '[<>:"\?\*\|]': _
    '\.$': _
    '\s+$': ''
    '\s+': ' '

# Plugins for enhanced organization
plugins: fetchart embedart duplicates scrub replaygain lastgenre info lyrics chroma edit

# Artwork fetching and embedding
fetchart:
    auto: yes
    cautious: true
    cover_names: cover folder album front art artwork
    sources: filesystem coverart itunes amazon albumart wikipedia
    store_source: yes
    high_resolution: yes
    maxwidth: 1000

embedart:
    auto: yes
    ifempty: no
    maxwidth: 1000
    remove_art_file: no

# Duplicate handling
duplicates:
    checksum: ffmpeg
    copy: /tmp/beets-duplicates/
    move: no
    delete: no
    full: no

# ReplayGain for consistent volume
replaygain:
    auto: yes
    backend: ffmpeg
    overwrite: no
    targetlevel: 89

# Genre enhancement
lastgenre:
    auto: yes
    source: album
    fallback: Electronic
    canonical: yes
    count: 1
    min_weight: 10
    title_case: yes
    separator: ', '

# Match settings for better accuracy
match:
    strong_rec_thresh: 0.04
    medium_rec_thresh: 0.25
    rec_gap_thresh: 0.25
    max_rec:
        missing_tracks: medium
        unmatched_tracks: medium
    distance_weights:
        source: 2.0
        artist: 3.0
        album: 3.0
        media: 1.0
        mediums: 1.0
        year: 1.0
        country: 0.5
        label: 0.5
        catalognum: 0.5
        albumdisambig: 0.5
        album_id: 5.0
        tracks: 2.0
        missing_tracks: 0.9
        unmatched_tracks: 0.6
        track_title: 3.0
        track_artist: 2.0
        track_index: 1.0
        track_length: 2.0
        track_id: 5.0

# Musicbrainz settings
musicbrainz:
    host: musicbrainz.org
    ratelimit: 1.0
    ratelimit_interval: 1.0

# UI settings
ui:
    color: yes
    length_diff_thresh: 10.0

# Logging
log: /tmp/beets-organization.log
verbose: 2
EOF

    print_success "✅ Beets configuration created"
}

# Backup existing library
create_backup() {
    if [[ "$SKIP_BACKUP" == true ]]; then
        print_warning "⚠️  Skipping backup as requested"
        return
    fi

    print_status "💾 Creating backup of current library..."

    if [[ "$DRY_RUN" == true ]]; then
        print_info "🧪 DRY RUN: Would create backup at $BACKUP_DIR"
        return
    fi

    mkdir -p "$BACKUP_DIR"

    print_info "Copying library to backup location..."
    rsync -av --progress "$MUSIC_LIBRARY/" "$BACKUP_DIR/"

    print_success "✅ Backup created at $BACKUP_DIR"
}

# Check prerequisites
check_prerequisites() {
    print_status "🔍 Checking prerequisites..."

    # Check if beets is installed
    if ! command -v beet &> /dev/null; then
        print_error "❌ Beets is not installed. Please install it first."
        exit 1
    fi

    # Check if source directory exists
    if [[ ! -d "$MUSIC_LIBRARY" ]]; then
        print_error "❌ Music library directory not found: $MUSIC_LIBRARY"
        exit 1
    fi

    # Check available space
    local source_size=$(du -sb "$MUSIC_LIBRARY" | cut -f1)
    local available_space=$(df "$MUSIC_LIBRARY" | tail -1 | awk '{print $4}')
    local available_bytes=$((available_space * 1024))

    if [[ $source_size -gt $available_bytes ]]; then
        print_error "❌ Insufficient space for organization"
        print_info "Required: $(numfmt --to=iec $source_size)"
        print_info "Available: $(numfmt --to=iec $available_bytes)"
        exit 1
    fi

    print_success "✅ Prerequisites check passed"
}

# Analyze current library
analyze_library() {
    print_status "📊 Analyzing current library structure..."

    local total_files=$(find "$MUSIC_LIBRARY" -type f -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.ogg" | wc -l)
    local total_size=$(du -sh "$MUSIC_LIBRARY" | cut -f1)
    local organized_folders=$(find "$MUSIC_LIBRARY" -maxdepth 2 -type d | wc -l)

    print_info "📁 Total music files: $total_files"
    print_info "💾 Total size: $total_size"
    print_info "📂 Current folders: $((organized_folders - 1))"

    # Check for already organized content
    if [[ -d "$MUSIC_LIBRARY/Armin van Buuren" ]]; then
        print_info "🎵 Found organized folder: Armin van Buuren"
    fi

    # Check for problematic files
    local problematic=$(find "$MUSIC_LIBRARY" -name "*[<>:\"|?*]*" | wc -l)
    if [[ $problematic -gt 0 ]]; then
        print_warning "⚠️  Found $problematic files with problematic characters"
    fi
}

# Organize library using beets
organize_library() {
    print_status "🎵 Starting library organization..."

    if [[ "$DRY_RUN" == true ]]; then
        print_info "🧪 DRY RUN: Would organize library using beets"
        print_info "Source: $MUSIC_LIBRARY"
        print_info "Destination: $ORGANIZED_LIBRARY"
        return
    fi

    # Create organized directory
    mkdir -p "$ORGANIZED_LIBRARY"

    # Import library with beets
    print_info "Running beets import..."

    export BEETSDIR=$(dirname "$BEETS_CONFIG")

    # Import with beets, handling user input
    if [[ "$FORCE" == true ]]; then
        # Auto-accept all matches in force mode
        beet -c "$BEETS_CONFIG" import -A "$MUSIC_LIBRARY" 2>&1 | tee -a "$LOG_FILE"
    else
        # Interactive mode for better control
        beet -c "$BEETS_CONFIG" import "$MUSIC_LIBRARY" 2>&1 | tee -a "$LOG_FILE"
    fi

    print_success "✅ Library organization completed"
}

# Verify organization results
verify_organization() {
    print_status "🔍 Verifying organization results..."

    if [[ ! -d "$ORGANIZED_LIBRARY" ]]; then
        print_error "❌ Organized library directory not found"
        return 1
    fi

    local organized_files=$(find "$ORGANIZED_LIBRARY" -type f -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.ogg" | wc -l)
    local organized_artists=$(find "$ORGANIZED_LIBRARY" -maxdepth 1 -type d | wc -l)
    local organized_size=$(du -sh "$ORGANIZED_LIBRARY" | cut -f1)

    print_info "📁 Organized files: $organized_files"
    print_info "🎤 Artist folders: $((organized_artists - 1))"
    print_info "💾 Organized size: $organized_size"

    # Check for artwork
    local artwork_count=$(find "$ORGANIZED_LIBRARY" -name "cover.jpg" -o -name "folder.jpg" -o -name "album.jpg" | wc -l)
    print_info "🖼️  Artwork files: $artwork_count"

    print_success "✅ Organization verification completed"
}

# Switch library directories
switch_libraries() {
    print_status "🔄 Switching to organized library..."

    if [[ "$DRY_RUN" == true ]]; then
        print_info "🧪 DRY RUN: Would switch libraries"
        return
    fi

    # Create a backup of the original flat structure
    local flat_backup="${MUSIC_LIBRARY}_flat_original"
    if [[ ! -d "$flat_backup" ]]; then
        mv "$MUSIC_LIBRARY" "$flat_backup"
        print_info "📁 Original flat library backed up to: $flat_backup"
    fi

    # Move organized library to the main location
    mv "$ORGANIZED_LIBRARY" "$MUSIC_LIBRARY"

    print_success "✅ Library switch completed"
}

# Restart Navidrome to rescan
restart_navidrome() {
    print_status "🔄 Restarting Navidrome for library rescan..."

    if [[ "$DRY_RUN" == true ]]; then
        print_info "🧪 DRY RUN: Would restart Navidrome"
        return
    fi

    if command -v docker &> /dev/null; then
        if docker ps --format "table {{.Names}}" | grep -q "stepheybot_music_navidrome"; then
            docker restart stepheybot_music_navidrome
            print_success "✅ Navidrome restarted"

            # Wait for scan to begin
            print_info "⏳ Waiting for library scan to begin..."
            sleep 10

            # Show scan progress
            print_info "📊 Check scan progress with: docker logs stepheybot_music_navidrome --tail 20"
        else
            print_warning "⚠️  Navidrome container not found"
        fi
    else
        print_warning "⚠️  Docker not available - please restart Navidrome manually"
    fi
}

# Cleanup temporary files
cleanup() {
    print_status "🧹 Cleaning up temporary files..."

    if [[ -f "$BEETS_CONFIG" ]]; then
        rm -f "$BEETS_CONFIG"
    fi

    if [[ -f "/tmp/stepheybot-organization.db" ]]; then
        rm -f "/tmp/stepheybot-organization.db"
    fi

    if [[ -d "/tmp/beets-duplicates" ]]; then
        rm -rf "/tmp/beets-duplicates"
    fi

    print_success "✅ Cleanup completed"
}

# Main execution
main() {
    print_neon_header

    print_neon "🎵 Starting StepheyBot Music Library Organization 🎵"
    print_info "Log file: $LOG_FILE"
    print_info "Target: $MUSIC_LIBRARY"

    if [[ "$DRY_RUN" == true ]]; then
        print_warning "🧪 DRY RUN MODE - No changes will be made"
    fi

    # Confirmation prompt
    if [[ "$FORCE" != true && "$DRY_RUN" != true ]]; then
        echo ""
        print_warning "⚠️  This will reorganize your entire music library!"
        print_info "Current flat structure will be transformed into Artist/Album folders"
        print_info "A backup will be created automatically"
        echo ""
        read -p "$(echo -e "${YELLOW}Continue with organization? (y/N): ${NC}")" -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "❌ Organization cancelled by user"
            exit 0
        fi
    fi

    # Execute organization steps
    check_prerequisites
    analyze_library
    create_beets_config
    create_backup
    organize_library
    verify_organization
    switch_libraries
    restart_navidrome
    cleanup

    # Final summary
    echo ""
    print_neon "🎉 StepheyBot Music Library Organization Complete! 🎉"
    print_success "Your music library is now properly organized for music.stepheybot.dev"
    print_info "📁 Organized library: $MUSIC_LIBRARY"
    print_info "💾 Backup location: $BACKUP_DIR"
    print_info "📝 Log file: $LOG_FILE"
    echo ""
    print_neon "🎵 Ready for optimal StepheyBot Music experience! 🎵"
}

# Error handling
trap cleanup EXIT

# Execute main function
main "$@"
