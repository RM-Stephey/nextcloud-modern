#!/bin/bash

# StepheyBot Music Library Test Organizer
# Tests organization on a small sample before full library transformation
# Usage: ./test-organize-sample.sh [--force]

set -euo pipefail

# Colors for neon-themed output
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
PINK='\033[1;95m'
NC='\033[0m'

# Configuration
MUSIC_LIBRARY="/mnt/hdd/media/music/library"
TEST_SOURCE="/tmp/stepheybot-music-test-source"
TEST_ORGANIZED="/tmp/stepheybot-music-test-organized"
BEETS_CONFIG="/tmp/stepheybot-test-beets-config.yaml"
LOG_FILE="/tmp/music-test-organization-$(date +%Y%m%d-%H%M%S).log"
SAMPLE_SIZE=15

# Flags
FORCE=false

# Neon-themed output functions
print_neon_header() {
    echo -e "${PINK}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PINK}║${CYAN}              🎵 StepheyBot Music Test Organizer 🎵             ${PINK}║${NC}"
    echo -e "${PINK}║${BLUE}                Test Organization on Small Sample              ${PINK}║${NC}"
    echo -e "${PINK}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_status() {
    echo -e "${BLUE}[TestBot]${NC} $1" | tee -a "$LOG_FILE"
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

# Parse arguments
for arg in "$@"; do
    case $arg in
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "StepheyBot Music Test Organizer"
            echo "Usage: $0 [--force]"
            echo ""
            echo "Creates a small test sample and organizes it to preview the results"
            echo "This is safe and doesn't modify your original library"
            exit 0
            ;;
        *)
            print_error "Unknown option: $arg"
            exit 1
            ;;
    esac
done

# Create beets test configuration
create_test_beets_config() {
    print_status "📝 Creating test beets configuration..."

    cat > "$BEETS_CONFIG" << EOF
# StepheyBot Test Configuration
directory: $TEST_ORGANIZED
library: /tmp/stepheybot-test.db

import:
    write: yes
    copy: yes
    move: no
    resume: yes
    incremental: no
    quiet_fallback: skip
    timid: no
    log: /tmp/beets-test-import.log
    duplicate_action: skip
    bell: no

# Path formatting - StepheyBot structure
paths:
    default: \$albumartist/\$album%aunique{}/\$track - \$title
    singleton: _Singles/\$artist/\$title
    comp: _Compilations/\$album%aunique{}/\$track - \$title
    albumtype:soundtrack: _Soundtracks/\$album/\$track - \$title

# Character replacement
replace:
    '[\\\\/]': _
    '^\\.': _
    '[\\x00-\\x1f]': _
    '[<>:\"\\?\\*\\|]': _
    '\\.\$': _
    '\\s+\$': ''
    '\\s+': ' '

# Essential plugins for testing
plugins: fetchart embedart info

# Artwork settings
fetchart:
    auto: yes
    cautious: true
    cover_names: cover folder album front art
    sources: filesystem coverart
    store_source: yes

embedart:
    auto: yes
    ifempty: no
    maxwidth: 800
    remove_art_file: no

# Match settings
match:
    strong_rec_thresh: 0.04
    medium_rec_thresh: 0.25

# UI settings
ui:
    color: yes
    length_diff_thresh: 10.0

# Logging
log: /tmp/beets-test.log
verbose: 2
EOF

    print_success "✅ Test beets configuration created"
}

# Create test sample from library
create_test_sample() {
    print_status "🎲 Creating test sample from library..."

    # Clean up previous test
    rm -rf "$TEST_SOURCE" "$TEST_ORGANIZED"
    mkdir -p "$TEST_SOURCE"

    # Find diverse sample of music files
    local sample_files=()

    # Get a variety of files from different parts of the library
    mapfile -t all_files < <(find "$MUSIC_LIBRARY" -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" \) | head -50)

    # Select diverse sample
    local step=$((${#all_files[@]} / SAMPLE_SIZE))
    if [[ $step -eq 0 ]]; then
        step=1
    fi

    for ((i=0; i<${#all_files[@]} && ${#sample_files[@]}<SAMPLE_SIZE; i+=step)); do
        sample_files+=("${all_files[i]}")
    done

    # Add our known organized track if it exists
    if [[ -f "$MUSIC_LIBRARY/Armin van Buuren/A State Of Trance 1231 (2025)/A State Of Trance 1231.mp3" ]]; then
        sample_files+=("$MUSIC_LIBRARY/Armin van Buuren/A State Of Trance 1231 (2025)/A State Of Trance 1231.mp3")

        # Copy the cover art too
        if [[ -f "$MUSIC_LIBRARY/Armin van Buuren/A State Of Trance 1231 (2025)/cover.jpg" ]]; then
            sample_files+=("$MUSIC_LIBRARY/Armin van Buuren/A State Of Trance 1231 (2025)/cover.jpg")
        fi
    fi

    # Copy sample files to test directory
    print_info "📁 Copying ${#sample_files[@]} sample files..."

    local copied=0
    for file in "${sample_files[@]}"; do
        if [[ -f "$file" ]]; then
            cp "$file" "$TEST_SOURCE/"
            ((copied++))

            # Show some examples
            if [[ $copied -le 5 ]]; then
                print_info "   📄 $(basename "$file")"
            fi
        fi
    done

    if [[ $copied -gt 5 ]]; then
        print_info "   ... and $((copied - 5)) more files"
    fi

    print_success "✅ Test sample created with $copied files"
}

# Run test organization
run_test_organization() {
    print_status "🎵 Running test organization..."

    mkdir -p "$TEST_ORGANIZED"

    export BEETSDIR=$(dirname "$BEETS_CONFIG")

    # Run beets import on test sample
    if [[ "$FORCE" == true ]]; then
        beet -c "$BEETS_CONFIG" import -A "$TEST_SOURCE" 2>&1 | tee -a "$LOG_FILE"
    else
        # Interactive mode for better testing
        print_info "🎮 Running in interactive mode (press 'a' to accept matches)"
        beet -c "$BEETS_CONFIG" import "$TEST_SOURCE" 2>&1 | tee -a "$LOG_FILE"
    fi

    print_success "✅ Test organization completed"
}

# Show organization results
show_results() {
    print_status "📊 Analyzing test organization results..."

    if [[ ! -d "$TEST_ORGANIZED" ]]; then
        print_error "❌ Test organized directory not found"
        return 1
    fi

    print_neon "🎯 ORGANIZATION PREVIEW:"
    echo ""

    # Show directory structure
    print_info "📁 Organized Directory Structure:"
    tree "$TEST_ORGANIZED" -L 3 2>/dev/null || find "$TEST_ORGANIZED" -type d | head -20

    echo ""

    # Count results
    local organized_files=$(find "$TEST_ORGANIZED" -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" \) | wc -l)
    local artist_folders=$(find "$TEST_ORGANIZED" -maxdepth 1 -type d ! -path "$TEST_ORGANIZED" | wc -l)
    local album_folders=$(find "$TEST_ORGANIZED" -maxdepth 2 -type d ! -path "$TEST_ORGANIZED" | wc -l)
    local artwork_files=$(find "$TEST_ORGANIZED" -name "cover.*" -o -name "folder.*" -o -name "album.*" | wc -l)

    print_info "📊 Organization Statistics:"
    print_info "   🎵 Music files organized: $organized_files"
    print_info "   🎤 Artist folders created: $artist_folders"
    print_info "   💿 Album folders created: $((album_folders - artist_folders))"
    print_info "   🖼️  Artwork files: $artwork_files"

    echo ""

    # Show some example paths
    print_info "📝 Example organized paths:"
    find "$TEST_ORGANIZED" -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" | head -5 | while read -r file; do
        local rel_path="${file#$TEST_ORGANIZED/}"
        print_info "   📄 $rel_path"
    done

    echo ""

    # Check for Armin van Buuren specifically
    if find "$TEST_ORGANIZED" -name "*Armin*" -type d | head -1 | read -r armin_dir; then
        print_neon "🎯 Found Armin van Buuren organization:"
        find "$armin_dir" -type f | head -3 | while read -r file; do
            local rel_path="${file#$TEST_ORGANIZED/}"
            print_info "   🎵 $rel_path"
        done
    fi

    print_success "✅ Test results analysis completed"
}

# Provide recommendations
provide_recommendations() {
    print_neon "💡 RECOMMENDATIONS FOR FULL ORGANIZATION:"
    echo ""

    print_info "✅ If the structure looks good:"
    print_info "   Run: ./organize-music-library.sh"
    print_info "   Or:  ./organize-music-library.sh --force (skip prompts)"
    echo ""

    print_info "⚙️  To modify organization:"
    print_info "   Edit the beets config in organize-music-library.sh"
    print_info "   Adjust path formats or plugin settings"
    echo ""

    print_info "🔍 To explore test results:"
    print_info "   Browse: $TEST_ORGANIZED"
    print_info "   Check logs: $LOG_FILE"
    echo ""

    print_warning "⚠️  Remember: Test files will be cleaned up on exit"
}

# Cleanup function
cleanup() {
    print_status "🧹 Cleaning up test files..."

    rm -rf "$TEST_SOURCE" "$TEST_ORGANIZED"
    rm -f "$BEETS_CONFIG" "/tmp/stepheybot-test.db" "/tmp/beets-test.log" "/tmp/beets-test-import.log"

    print_success "✅ Test cleanup completed"
}

# Main execution
main() {
    print_neon_header

    print_neon "🧪 Testing StepheyBot Music Organization 🧪"
    print_info "This is a safe test that won't modify your library"
    print_info "Log file: $LOG_FILE"

    # Confirmation for interactive mode
    if [[ "$FORCE" != true ]]; then
        echo ""
        print_info "📋 This test will:"
        print_info "  1. Copy $SAMPLE_SIZE sample files to temporary location"
        print_info "  2. Organize them using beets"
        print_info "  3. Show you the resulting structure"
        print_info "  4. Clean up test files"
        echo ""
        read -p "$(echo -e "${YELLOW}Continue with test? (Y/n): ${NC}")" -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            print_info "❌ Test cancelled by user"
            exit 0
        fi
    fi

    # Check prerequisites
    if ! command -v beet &> /dev/null; then
        print_error "❌ Beets is not installed. Please install it first."
        exit 1
    fi

    if [[ ! -d "$MUSIC_LIBRARY" ]]; then
        print_error "❌ Music library not found: $MUSIC_LIBRARY"
        exit 1
    fi

    # Run test steps
    create_test_beets_config
    create_test_sample
    run_test_organization
    show_results
    provide_recommendations

    echo ""
    print_neon "🎉 Test Organization Complete! 🎉"
    print_success "Review the results above to decide on full organization"
}

# Error handling
trap cleanup EXIT

# Execute main function
main "$@"
