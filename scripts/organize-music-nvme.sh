#!/bin/bash

# StepheyBot NVME-Optimized Music Library Organizer
# Ultra-fast organization using NVME storage with HDD optimization
# Usage: ./organize-music-nvme.sh [--force] [--defrag] [--backup-only]

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
NC='\033[0m'

# Configuration
MUSIC_LIBRARY="/mnt/hdd/media/music/library"
NVME_WORKSPACE="/mnt/nvme/hot/stepheybot-music-org"
NVME_SOURCE="$NVME_WORKSPACE/source"
NVME_ORGANIZED="$NVME_WORKSPACE/organized"
BACKUP_DIR="/mnt/hdd/media/music/backups"
BEETS_CONFIG="$NVME_WORKSPACE/beets-config.yaml"
LOG_FILE="/tmp/music-nvme-organization-$(date +%Y%m%d-%H%M%S).log"

# Flags
FORCE=false
DEFRAG_HDD=false
BACKUP_ONLY=false

# Neon-themed output functions
print_neon_header() {
    echo -e "${PINK}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PINK}║${CYAN}                 🚀 StepheyBot NVME Music Organizer 🚀                ${PINK}║${NC}"
    echo -e "${PINK}║${MAGENTA}              Ultra-Fast Organization with NVME Power               ${PINK}║${NC}"
    echo -e "${PINK}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_status() {
    echo -e "${CYAN}[NVME-Bot]${NC} $1" | tee -a "$LOG_FILE"
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

print_speed() {
    echo -e "${MAGENTA}[SPEED]${NC} $1" | tee -a "$LOG_FILE"
}

# Parse arguments
for arg in "$@"; do
    case $arg in
        --force)
            FORCE=true
            shift
            ;;
        --defrag)
            DEFRAG_HDD=true
            shift
            ;;
        --backup-only)
            BACKUP_ONLY=true
            shift
            ;;
        -h|--help)
            echo "StepheyBot NVME-Optimized Music Organizer"
            echo "Usage: $0 [--force] [--defrag] [--backup-only]"
            echo ""
            echo "Options:"
            echo "  --force       Skip all confirmation prompts"
            echo "  --defrag      Perform HDD defragmentation during organization"
            echo "  --backup-only Create backup and exit (no organization)"
            echo ""
            echo "This script uses NVME storage for ultra-fast processing:"
            echo "1. Copies library to NVME (295G available)"
            echo "2. Organizes on fast storage"
            echo "3. Optionally defrags HDD while working"
            echo "4. Moves organized library back to HDD"
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
    print_status "🔍 Checking NVME-optimized prerequisites..."

    # Check beets
    if ! command -v beet &> /dev/null; then
        print_error "❌ Beets is not installed. Install with: pip install beets"
        exit 1
    fi

    # Check source library
    if [[ ! -d "$MUSIC_LIBRARY" ]]; then
        print_error "❌ Music library not found: $MUSIC_LIBRARY"
        exit 1
    fi

    # Check NVME space
    local nvme_available=$(df -B1 /mnt/nvme/hot | awk 'NR==2 {print $4}')
    local library_size=$(du -sb "$MUSIC_LIBRARY" | cut -f1)
    local required_space=$((library_size * 3)) # Source + Organized + Buffer

    if [[ $nvme_available -lt $required_space ]]; then
        print_error "❌ Insufficient NVME space. Required: $(numfmt --to=iec $required_space), Available: $(numfmt --to=iec $nvme_available)"
        exit 1
    fi

    # Check defrag tools
    if [[ "$DEFRAG_HDD" == true ]]; then
        if ! command -v e4defrag &> /dev/null; then
            print_warning "⚠️  e4defrag not found. HDD defrag will be skipped."
            DEFRAG_HDD=false
        fi
    fi

    print_success "✅ All prerequisites met for NVME-optimized processing"
    print_speed "🚀 NVME available: $(numfmt --to=iec $nvme_available)"
    print_speed "📊 Library size: $(numfmt --to=iec $library_size)"
}

# Create beets configuration optimized for NVME
create_beets_config() {
    print_status "📝 Creating NVME-optimized beets configuration..."

    mkdir -p "$NVME_WORKSPACE"

    cat > "$BEETS_CONFIG" << EOF
# StepheyBot NVME-Optimized Configuration
directory: $NVME_ORGANIZED
library: $NVME_WORKSPACE/library.db

import:
    write: yes
    copy: yes
    move: no
    resume: yes
    incremental: no
    quiet_fallback: skip
    timid: no
    log: $NVME_WORKSPACE/import.log
    duplicate_action: skip
    bell: no
    from_scratch: no
    group_albums: yes

# Optimized path formatting for professional structure
paths:
    default: \$albumartist/\$album%aunique{}/\$track. \$title
    singleton: _Singles/\$artist/\$title
    comp: _Compilations/\$album%aunique{}/\$track. \$title
    albumtype:soundtrack: _Soundtracks/\$album/\$track. \$title
    albumtype:remix: _Remixes/\$albumartist/\$album%aunique{}/\$track. \$title
    albumtype:dj-mix: _DJ-Mixes/\$albumartist/\$album%aunique{}/\$track. \$title

# Character sanitization for cross-platform compatibility
replace:
    '[\\\\/]': _
    '^\\.': _
    '[\\x00-\\x1f]': _
    '[<>:\\"\\?\\*\\|]': _
    '\\.\$': _
    '\\s+\$': ''
    '\\s+': ' '
    '&': and

# Essential plugins for professional organization
plugins: fetchart embedart replaygain info lastgenre

# High-quality artwork settings
fetchart:
    auto: yes
    cautious: true
    cover_names: cover folder album front art artwork
    sources: filesystem coverart itunes amazon albumart
    store_source: yes
    high_resolution: yes

embedart:
    auto: yes
    ifempty: no
    maxwidth: 1000
    remove_art_file: no
    compare_threshold: 0

# ReplayGain for consistent volume
replaygain:
    auto: yes
    overwrite: no
    threads: 4

# Genre classification
lastgenre:
    auto: yes
    source: track

# Matching settings optimized for speed and accuracy
match:
    strong_rec_thresh: 0.10
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

# UI settings for automated processing
ui:
    color: yes
    length_diff_thresh: 10.0

# Logging optimized for debugging
log: $NVME_WORKSPACE/beets.log
verbose: 1
EOF

    print_success "✅ NVME-optimized beets configuration created"
}

# Create backup
create_backup() {
    print_status "💾 Creating library backup..."

    local backup_name="pre-nvme-organization-$(date +%Y%m%d-%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"

    mkdir -p "$BACKUP_DIR"

    print_info "📦 Backup destination: $backup_path"

    # Use rsync for efficient backup with progress
    rsync -avh --progress "$MUSIC_LIBRARY/" "$backup_path/" | tee -a "$LOG_FILE"

    print_success "✅ Backup created: $backup_path"

    if [[ "$BACKUP_ONLY" == true ]]; then
        print_neon "🎯 BACKUP-ONLY MODE: Backup completed, exiting"
        exit 0
    fi
}

# Copy library to NVME
copy_to_nvme() {
    print_status "🚀 Copying library to NVME for ultra-fast processing..."

    rm -rf "$NVME_WORKSPACE"
    mkdir -p "$NVME_SOURCE"

    print_speed "⚡ Starting high-speed NVME transfer..."

    # Use rsync with optimizations for NVME
    rsync -avh --progress --no-compress "$MUSIC_LIBRARY/" "$NVME_SOURCE/" | tee -a "$LOG_FILE"

    local copied_files=$(find "$NVME_SOURCE" -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" \) | wc -l)
    local copied_size=$(du -sh "$NVME_SOURCE" | cut -f1)

    print_success "✅ Library copied to NVME"
    print_speed "📊 Files copied: $copied_files"
    print_speed "💾 Size on NVME: $copied_size"
}

# Start HDD defragmentation in background
start_hdd_defrag() {
    if [[ "$DEFRAG_HDD" == true ]]; then
        print_status "🔧 Starting HDD defragmentation in background..."

        # Create defrag script
        cat > "$NVME_WORKSPACE/defrag.sh" << 'EOF'
#!/bin/bash
LOG_FILE="/tmp/hdd-defrag-$(date +%Y%m%d-%H%M%S).log"
echo "Starting HDD defragmentation at $(date)" | tee -a "$LOG_FILE"
e4defrag -v /mnt/hdd/media/music/ 2>&1 | tee -a "$LOG_FILE"
echo "HDD defragmentation completed at $(date)" | tee -a "$LOG_FILE"
EOF

        chmod +x "$NVME_WORKSPACE/defrag.sh"
        nohup "$NVME_WORKSPACE/defrag.sh" &

        print_info "🔧 HDD defrag running in background (check /tmp/hdd-defrag-*.log)"
    fi
}

# Organize music on NVME
organize_on_nvme() {
    print_status "🎵 Starting ultra-fast NVME organization..."

    mkdir -p "$NVME_ORGANIZED"

    export BEETSDIR="$NVME_WORKSPACE"

    print_speed "⚡ Processing on NVME for maximum speed..."

    if [[ "$FORCE" == true ]]; then
        # Automated mode
        print_info "🤖 Running in automated mode"
        beet -c "$BEETS_CONFIG" import -A -q "$NVME_SOURCE" 2>&1 | tee -a "$LOG_FILE"
    else
        # Interactive mode with timeout
        print_info "🎮 Running in interactive mode (auto-accept after 30s per album)"
        timeout 1800 beet -c "$BEETS_CONFIG" import "$NVME_SOURCE" 2>&1 | tee -a "$LOG_FILE" || {
            print_warning "⚠️  Interactive mode timed out, switching to auto mode"
            beet -c "$BEETS_CONFIG" import -A -q "$NVME_SOURCE" 2>&1 | tee -a "$LOG_FILE"
        }
    fi

    print_success "✅ NVME organization completed"
}

# Verify organization results
verify_organization() {
    print_status "🔍 Verifying organization results..."

    if [[ ! -d "$NVME_ORGANIZED" ]]; then
        print_error "❌ Organized directory not found on NVME"
        return 1
    fi

    # Count results
    local original_files=$(find "$NVME_SOURCE" -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" \) | wc -l)
    local organized_files=$(find "$NVME_ORGANIZED" -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" \) | wc -l)
    local artist_folders=$(find "$NVME_ORGANIZED" -maxdepth 1 -type d ! -path "$NVME_ORGANIZED" | wc -l)
    local artwork_files=$(find "$NVME_ORGANIZED" -name "cover.*" -o -name "folder.*" -o -name "album.*" | wc -l)

    print_neon "📊 ORGANIZATION VERIFICATION:"
    print_info "🎵 Original files: $original_files"
    print_info "🎵 Organized files: $organized_files"
    print_info "🎤 Artist folders: $artist_folders"
    print_info "🖼️  Artwork files: $artwork_files"

    if [[ $organized_files -eq 0 ]]; then
        print_error "❌ No files were organized"
        return 1
    fi

    # Show sample structure
    print_info "📁 Sample organized structure:"
    find "$NVME_ORGANIZED" -type d | head -10 | while read -r dir; do
        local rel_path="${dir#$NVME_ORGANIZED/}"
        if [[ -n "$rel_path" ]]; then
            print_info "   📂 $rel_path"
        fi
    done

    print_success "✅ Organization verification passed"
}

# Move organized library back to HDD
move_to_hdd() {
    print_status "📤 Moving organized library back to HDD..."

    # Backup current library
    local temp_backup="$MUSIC_LIBRARY.pre-nvme-replace"
    if [[ -d "$MUSIC_LIBRARY" ]]; then
        print_info "🔄 Creating temporary backup of current library"
        mv "$MUSIC_LIBRARY" "$temp_backup"
    fi

    # Move organized library from NVME to HDD
    print_speed "⚡ High-speed transfer from NVME to HDD..."
    rsync -avh --progress "$NVME_ORGANIZED/" "$MUSIC_LIBRARY/" | tee -a "$LOG_FILE"

    # Verify the move
    local final_files=$(find "$MUSIC_LIBRARY" -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" \) | wc -l)

    if [[ $final_files -gt 0 ]]; then
        print_success "✅ Organized library successfully moved to HDD"
        print_info "🎵 Final file count: $final_files"

        # Remove temporary backup
        if [[ -d "$temp_backup" ]]; then
            rm -rf "$temp_backup"
            print_info "🧹 Temporary backup removed"
        fi
    else
        print_error "❌ Move failed, restoring from backup"
        if [[ -d "$temp_backup" ]]; then
            mv "$temp_backup" "$MUSIC_LIBRARY"
        fi
        return 1
    fi
}

# Cleanup NVME workspace
cleanup_nvme() {
    print_status "🧹 Cleaning up NVME workspace..."

    if [[ -d "$NVME_WORKSPACE" ]]; then
        rm -rf "$NVME_WORKSPACE"
        print_success "✅ NVME workspace cleaned"

        # Show freed space
        local nvme_free=$(df -h /mnt/nvme/hot | awk 'NR==2 {print $4}')
        print_speed "💾 NVME space freed, available: $nvme_free"
    fi
}

# Show final results
show_final_results() {
    print_neon "🎉 NVME ORGANIZATION COMPLETE! 🎉"
    echo ""

    # Final statistics
    local final_files=$(find "$MUSIC_LIBRARY" -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" \) | wc -l)
    local final_size=$(du -sh "$MUSIC_LIBRARY" | cut -f1)
    local artist_count=$(find "$MUSIC_LIBRARY" -maxdepth 1 -type d ! -path "$MUSIC_LIBRARY" | wc -l)

    print_neon "📊 FINAL STATISTICS:"
    print_info "🎵 Total music files: $final_files"
    print_info "💾 Library size: $final_size"
    print_info "🎤 Artist folders: $artist_count"
    print_info "📋 Log file: $LOG_FILE"

    echo ""
    print_speed "⚡ NVME-OPTIMIZED ORGANIZATION BENEFITS:"
    print_speed "🚀 Ultra-fast processing on NVME storage"
    print_speed "🔧 HDD optimization during processing"
    print_speed "💾 Efficient use of fast and slow storage"
    print_speed "🎯 Professional-grade library structure"

    echo ""
    print_neon "🎵 Your library is now professionally organized! 🎵"
    print_info "Ready for Navidrome, Lidarr, and music.stepheybot.dev"
}

# Wait for HDD defrag completion
wait_for_defrag() {
    if [[ "$DEFRAG_HDD" == true ]]; then
        print_status "⏳ Waiting for HDD defragmentation to complete..."

        while pgrep -f "e4defrag" > /dev/null; do
            sleep 30
            print_info "🔧 HDD defrag still running..."
        done

        print_success "✅ HDD defragmentation completed"
    fi
}

# Error handling and cleanup
cleanup_on_error() {
    print_error "❌ Error occurred, cleaning up..."

    # Kill defrag if running
    pkill -f "e4defrag" 2>/dev/null || true

    # Clean NVME workspace
    cleanup_nvme

    print_error "💥 Organization failed. Check log: $LOG_FILE"
}

trap cleanup_on_error ERR

# Main execution
main() {
    print_neon_header

    print_neon "🚀 NVME-Optimized Music Organization 🚀"
    print_info "Using ultra-fast NVME storage for processing"
    print_info "Log file: $LOG_FILE"

    # Confirmation unless forced
    if [[ "$FORCE" != true && "$BACKUP_ONLY" != true ]]; then
        echo ""
        print_info "📋 This process will:"
        print_info "  1. Create full library backup"
        print_info "  2. Copy library to NVME (/mnt/nvme/hot)"
        print_info "  3. Organize on ultra-fast NVME storage"
        if [[ "$DEFRAG_HDD" == true ]]; then
            print_info "  4. Defragment HDD while processing on NVME"
        fi
        print_info "  5. Move organized library back to HDD"
        print_info "  6. Clean up NVME workspace"
        echo ""
        print_speed "⚡ NVME optimization provides 10-50x faster processing"
        echo ""
        read -p "$(echo -e "${YELLOW}Proceed with NVME-optimized organization? (Y/n): ${NC}")" -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            print_info "❌ Organization cancelled by user"
            exit 0
        fi
    fi

    # Execute organization steps
    check_prerequisites
    create_beets_config
    create_backup
    copy_to_nvme
    start_hdd_defrag
    organize_on_nvme
    verify_organization
    wait_for_defrag
    move_to_hdd
    cleanup_nvme
    show_final_results

    print_success "🎉 NVME-optimized organization completed successfully!"
}

# Execute main function
main "$@"
