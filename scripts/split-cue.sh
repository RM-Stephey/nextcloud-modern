#!/bin/bash

# StepheyBot Music System - CUE File Splitter
# Splits DJ mixes and compilations based on CUE files
# Usage: ./split-cue.sh "path/to/file.cue" [output_directory]

set -euo pipefail

# Colors for output (neon theme for Stephey!)
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[StepheyBot]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

# Check if required tools are available
check_dependencies() {
    local deps=("ffmpeg" "awk" "sed")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            print_error "$dep is required but not installed"
            exit 1
        fi
    done
}

# Convert CUE timestamp (MM:SS:FF) to seconds
cue_time_to_seconds() {
    local cue_time="$1"
    local minutes seconds frames

    IFS=':' read -r minutes seconds frames <<< "$cue_time"

    # Remove leading zeros to avoid octal interpretation
    minutes=$((10#$minutes))
    seconds=$((10#$seconds))
    frames=$((10#$frames))

    # Convert to total seconds (75 frames per second in CUE format)
    local total_seconds=$(echo "scale=3; $minutes * 60 + $seconds + $frames / 75" | bc -l)
    echo "$total_seconds"
}

# Parse CUE file and extract track information
parse_cue_file() {
    local cue_file="$1"
    local temp_tracks="/tmp/cue_tracks_$$"

    # Extract basic album info (global variables)
    ALBUM_ARTIST=$(grep -i "^PERFORMER" "$cue_file" | head -1 | sed 's/^PERFORMER "\(.*\)"$/\1/' || echo "Unknown Artist")
    ALBUM_TITLE=$(grep -i "^TITLE" "$cue_file" | head -1 | sed 's/^TITLE "\(.*\)"$/\1/' || echo "Unknown Album")
    AUDIO_FILE=$(grep -i "^FILE" "$cue_file" | sed 's/^FILE "\(.*\)" .*$/\1/' || echo "")

    print_info "Album: $ALBUM_ARTIST - $ALBUM_TITLE"
    print_info "Audio file: $AUDIO_FILE"

    # Parse tracks
    awk '
    BEGIN { track_num = 0; in_track = 0 }
    /^  TRACK [0-9]+ AUDIO/ {
        if (in_track) {
            print track_num "|||" title "|||" performer "|||" start_time
        }
        match($0, /TRACK ([0-9]+)/, arr)
        track_num = arr[1]
        in_track = 1
        title = ""
        performer = ""
        start_time = ""
    }
    /^    TITLE/ {
        if (in_track) {
            gsub(/^    TITLE "/, "")
            gsub(/"$/, "")
            title = $0
        }
    }
    /^    PERFORMER/ {
        if (in_track) {
            gsub(/^    PERFORMER "/, "")
            gsub(/"$/, "")
            performer = $0
        }
    }
    /^    INDEX 01/ {
        if (in_track) {
            start_time = $3
        }
    }
    END {
        if (in_track) {
            print track_num "|||" title "|||" performer "|||" start_time
        }
    }
    ' "$cue_file" > "$temp_tracks"

    echo "$temp_tracks"
}

# Split audio file based on track information
split_audio() {
    local audio_file="$1"
    local tracks_file="$2"
    local output_dir="$3"

    local track_count=$(wc -l < "$tracks_file")
    print_info "Processing $track_count tracks..."

    local prev_end_time="0"
    local line_num=0

    while IFS='|||' read -r track_num title performer start_time; do
        line_num=$((line_num + 1))

        # Skip empty lines
        [[ -z "$track_num" ]] && continue

        # Convert CUE time to seconds
        local start_seconds=$(cue_time_to_seconds "$start_time")

        # Calculate duration for this track
        local duration=""
        if [[ $line_num -lt $track_count ]]; then
            # Get next track's start time
            local next_line=$(sed -n "$((line_num + 1))p" "$tracks_file")
            local next_start_time=$(echo "$next_line" | cut -d'|||' -f4)
            local next_start_seconds=$(cue_time_to_seconds "$next_start_time")
            duration="-t $(echo "scale=3; $next_start_seconds - $start_seconds" | bc -l)"
        fi

        # Clean up track title and performer for filename
        local clean_title=$(echo "$title" | sed 's/[^A-Za-z0-9 _-]//g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
        local clean_performer=$(echo "$performer" | sed 's/[^A-Za-z0-9 _-]//g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')

        # Create output filename
        local output_file="$output_dir/$(printf "%02d" "$track_num") - $clean_title.mp3"

        print_status "Extracting: $(printf "%02d" "$track_num") - $clean_title"

        # Use ffmpeg to extract the track
        ffmpeg -i "$audio_file" \
               -ss "$start_seconds" \
               $duration \
               -acodec libmp3lame \
               -b:a 320k \
               -metadata title="$title" \
               -metadata artist="$clean_performer" \
               -metadata album="$ALBUM_TITLE" \
               -metadata albumartist="$ALBUM_ARTIST" \
               -metadata track="$track_num" \
               -y "$output_file" \
               2>/dev/null || {
            print_error "Failed to extract track $track_num"
            continue
        }

        print_success "Created: $(basename "$output_file")"

    done < "$tracks_file"
}

# Copy additional files (artwork, original CUE)
copy_additional_files() {
    local source_dir="$1"
    local output_dir="$2"

    # Copy artwork files
    find "$source_dir" -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" | while read -r img_file; do
        if [[ $(basename "$img_file") != *"pirate"* ]] && [[ $(basename "$img_file") != *"logo"* ]]; then
            cp "$img_file" "$output_dir/cover.jpg"
            print_success "Copied artwork: $(basename "$img_file") → cover.jpg"
        fi
    done

    # Copy original CUE file
    find "$source_dir" -name "*.cue" | while read -r cue_file; do
        cp "$cue_file" "$output_dir/album.cue"
        print_success "Preserved CUE file: $(basename "$cue_file") → album.cue"
    done
}

# Main function
main() {
    local cue_file="$1"
    local output_dir="${2:-$(dirname "$cue_file")/split}"

    # Validate input
    if [[ ! -f "$cue_file" ]]; then
        print_error "CUE file not found: $cue_file"
        exit 1
    fi

    if [[ "${cue_file##*.}" != "cue" ]]; then
        print_error "File is not a CUE file: $cue_file"
        exit 1
    fi

    print_status "🎵 StepheyBot CUE Splitter v1.0"
    print_status "Processing: $(basename "$cue_file")"

    # Create output directory
    mkdir -p "$output_dir"

    # Parse CUE file
    local tracks_file=$(parse_cue_file "$cue_file")

    # Validate that required variables were set
    if [[ -z "${AUDIO_FILE:-}" ]]; then
        print_error "Could not find audio file reference in CUE file"
        rm -f "$tracks_file"
        exit 1
    fi

    # Get the directory containing the CUE file
    local cue_dir=$(dirname "$cue_file")

    # Find the audio file (should be in same directory)
    local audio_file="$cue_dir/$AUDIO_FILE"
    if [[ ! -f "$audio_file" ]]; then
        print_error "Audio file not found: $audio_file"
        rm -f "$tracks_file"
        exit 1
    fi

    # Split the audio
    split_audio "$audio_file" "$tracks_file" "$output_dir"

    # Copy additional files
    copy_additional_files "$cue_dir" "$output_dir"

    # Cleanup
    rm -f "$tracks_file"

    print_success "🎉 CUE splitting complete!"
    print_info "Output directory: $output_dir"
    print_info "Tracks created: $(find "$output_dir" -name "*.mp3" | wc -l)"
}

# Check dependencies
check_dependencies

# Ensure bc is available for calculations
if ! command -v bc &> /dev/null; then
    print_error "bc (calculator) is required but not installed"
    print_info "Install with: sudo pacman -S bc"
    exit 1
fi

# Validate arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <cue_file> [output_directory]"
    echo "Example: $0 'album.cue' '/output/path'"
    exit 1
fi

# Run main function
main "$@"
