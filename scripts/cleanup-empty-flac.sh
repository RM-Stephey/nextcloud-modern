#!/bin/bash

# StepheyBot Music System - Empty FLAC File Cleanup
# Removes zero-byte FLAC files that cause Navidrome parsing errors
# Usage: ./cleanup-empty-flac.sh [--dry-run] [--force]

set -euo pipefail

# Colors for output (neon theme for Stephey!)
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
MUSIC_LIBRARY="/mnt/hdd/media/music/library"
BACKUP_DIR="/tmp/empty-flac-backup-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/tmp/flac-cleanup-$(date +%Y%m%d-%H%M%S).log"

# Function to print colored output
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

# Parse command line arguments
DRY_RUN=false
FORCE=false

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
        -h|--help)
            echo "Usage: $0 [--dry-run] [--force]"
            echo "  --dry-run  Show what would be deleted without actually deleting"
            echo "  --force    Skip confirmation prompts"
            exit 0
            ;;
        *)
            print_error "Unknown option: $arg"
            exit 1
            ;;
    esac
done

# Header
print_status "🎵 StepheyBot FLAC Cleanup Tool v1.0"
print_status "Target directory: $MUSIC_LIBRARY"
print_status "Log file: $LOG_FILE"

# Check if music library exists
if [[ ! -d "$MUSIC_LIBRARY" ]]; then
    print_error "Music library directory not found: $MUSIC_LIBRARY"
    exit 1
fi

# Find empty FLAC files
print_info "🔍 Scanning for empty FLAC files..."
mapfile -t empty_flacs < <(find "$MUSIC_LIBRARY" -name "*.flac" -size 0 2>/dev/null)

if [[ ${#empty_flacs[@]} -eq 0 ]]; then
    print_success "🎉 No empty FLAC files found! Your library is clean."
    exit 0
fi

print_warning "Found ${#empty_flacs[@]} empty FLAC files:"
echo "" | tee -a "$LOG_FILE"

# List found files
for file in "${empty_flacs[@]}"; do
    basename_file=$(basename "$file")
    print_info "  📁 $basename_file"
done

echo "" | tee -a "$LOG_FILE"

# Calculate space that would be freed (should be 0 for empty files)
total_size=$(find "$MUSIC_LIBRARY" -name "*.flac" -size 0 -exec ls -l {} \; 2>/dev/null | awk '{sum += $5} END {print sum+0}')
print_info "Total space to be freed: ${total_size} bytes"

# Dry run mode
if [[ "$DRY_RUN" == true ]]; then
    print_warning "🧪 DRY RUN MODE - No files will be deleted"
    print_info "Files that would be deleted:"
    for file in "${empty_flacs[@]}"; do
        echo "  - $file" | tee -a "$LOG_FILE"
    done
    print_info "Run without --dry-run to actually delete these files"
    exit 0
fi

# Confirmation prompt (unless --force)
if [[ "$FORCE" != true ]]; then
    echo ""
    print_warning "⚠️  This will permanently delete ${#empty_flacs[@]} empty FLAC files!"
    read -p "$(echo -e "${YELLOW}Are you sure? (y/N): ${NC}")" -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "❌ Operation cancelled by user"
        exit 0
    fi
fi

# Create backup directory for safety (even though files are empty)
print_info "📦 Creating backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# Process files
print_status "🗑️  Removing empty FLAC files..."
removed_count=0
failed_count=0

for file in "${empty_flacs[@]}"; do
    basename_file=$(basename "$file")

    # Create backup entry (just filename since file is empty)
    echo "$file" >> "$BACKUP_DIR/deleted-files.txt"

    # Attempt to remove file
    if rm -f "$file" 2>/dev/null; then
        print_success "✓ Removed: $basename_file"
        ((removed_count++))
    else
        print_error "✗ Failed to remove: $basename_file"
        ((failed_count++))
    fi
done

echo "" | tee -a "$LOG_FILE"

# Summary
print_status "🎯 Cleanup Summary:"
print_success "  ✅ Files removed: $removed_count"
if [[ $failed_count -gt 0 ]]; then
    print_error "  ❌ Files failed: $failed_count"
fi
print_info "  📋 Backup info: $BACKUP_DIR/deleted-files.txt"
print_info "  📝 Full log: $LOG_FILE"

# Verify cleanup
remaining_empty=$(find "$MUSIC_LIBRARY" -name "*.flac" -size 0 2>/dev/null | wc -l)
if [[ $remaining_empty -eq 0 ]]; then
    print_success "🎉 All empty FLAC files successfully removed!"
else
    print_warning "⚠️  $remaining_empty empty FLAC files still remain"
fi

# Suggest next steps
echo "" | tee -a "$LOG_FILE"
print_info "🚀 Next Steps:"
print_info "  1. Restart Navidrome: docker restart stepheybot_music_navidrome"
print_info "  2. Wait for rescan to complete"
print_info "  3. Check logs: docker logs stepheybot_music_navidrome --tail 20"
print_info "  4. Verify stats: curl -s http://localhost:8083/api/v1/navidrome/stats"

# Optional: Trigger Navidrome restart if Docker is available
if command -v docker &> /dev/null; then
    if [[ "$FORCE" == true ]] || [[ "$DRY_RUN" == false ]]; then
        echo ""
        read -p "$(echo -e "${CYAN}Restart Navidrome now? (y/N): ${NC}")" -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "🔄 Restarting Navidrome..."
            if docker restart stepheybot_music_navidrome &>/dev/null; then
                print_success "✅ Navidrome restarted successfully"
                print_info "⏳ Waiting for rescan to complete..."
                sleep 5
                print_info "Check status with: curl -s http://localhost:8083/api/v1/navidrome/stats"
            else
                print_error "❌ Failed to restart Navidrome"
                print_info "Manual restart: docker restart stepheybot_music_navidrome"
            fi
        fi
    fi
fi

print_success "🎵 FLAC cleanup completed!"
