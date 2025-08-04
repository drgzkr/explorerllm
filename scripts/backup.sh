#!/bin/bash

# ExplorerLLM Backup Script
# This script backs up your Ollama models and WebUI data
# Usage: ./backup.sh [backup_directory]

set -e  # Exit on any error

# Configuration
DEFAULT_BACKUP_DIR="/backups"
PROJECT_NAME="explorerllm"
DATE=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_usage() {
    echo "Usage: $0 [backup_directory]"
    echo ""
    echo "Options:"
    echo "  backup_directory  Directory to store backups (default: $DEFAULT_BACKUP_DIR)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Backup to $DEFAULT_BACKUP_DIR"
    echo "  $0 /home/user/backup  # Backup to custom directory"
}

check_dependencies() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed or not in PATH"
        exit 1
    fi
}

check_services() {
    if ! docker-compose ps | grep -q "Up"; then
        log_warn "Services don't appear to be running. Starting them first..."
        docker-compose up -d
        sleep 10
    fi
}

create_backup_dir() {
    local backup_dir=$1
    local full_backup_path="${backup_dir}/${PROJECT_NAME}_${DATE}"
    
    mkdir -p "$full_backup_path"
    echo "$full_backup_path"
}

backup_data() {
    local backup_path=$1
    local project_dir=$(pwd)
    
    log_info "Starting backup process..."
    
    # Stop services gracefully
    log_info "Stopping services..."
    docker-compose stop
    
    # Backup WebUI data (chat history, users, settings)
    log_info "Backing up WebUI data..."
    docker run --rm \
        -v ${project_dir##*/}_ollama_webui_data:/data \
        -v "$backup_path":/backup \
        ubuntu:latest \
        tar czf "/backup/webui-data_${DATE}.tar.gz" /data
    
    # Backup Ollama models
    log_info "Backing up Ollama models..."
    docker run --rm \
        -v ${project_dir##*/}_ollama_data:/data \
        -v "$backup_path":/backup \
        ubuntu:latest \
        tar czf "/backup/models_${DATE}.tar.gz" /data
    
    # Backup configuration files
    log_info "Backing up configuration files..."
    cp docker-compose.yml "$backup_path/"
    
    # Create backup manifest
    cat > "$backup_path/backup_manifest.txt" << EOF
ExplorerLLM Backup Manifest
==========================
Date: $(date)
Project Directory: $(pwd)
Docker Compose Project: ${project_dir##*/}

Files:
- webui-data_${DATE}.tar.gz    # WebUI data (users, chat history, settings)
- models_${DATE}.tar.gz        # Ollama models
- docker-compose.yml           # Docker Compose configuration

Volumes backed up:
- ${project_dir##*/}_ollama_webui_data
- ${project_dir##*/}_ollama_data

Restore command:
./scripts/restore.sh "$backup_path"
EOF
    
    # Restart services
    log_info "Restarting services..."
    docker-compose start
    
    # Wait for services to be ready
    sleep 10
    
    # Verify services are running
    if docker-compose ps | grep -q "Up"; then
        log_info "Services restarted successfully"
    else
        log_warn "Services may not have started properly. Check with: docker-compose ps"
    fi
}

cleanup_old_backups() {
    local backup_base_dir=$1
    local retention_days=${BACKUP_RETENTION_DAYS:-30}
    
    log_info "Cleaning up backups older than $retention_days days..."
    
    # Find and remove old backup directories
    find "$backup_base_dir" -name "${PROJECT_NAME}_*" -type d -mtime +$retention_days -exec rm -rf {} + 2>/dev/null || true
    
    # Find and remove old backup files (in case someone stored them differently)
    find "$backup_base_dir" -name "*${PROJECT_NAME}*" -name "*.tar.gz" -mtime +$retention_days -delete 2>/dev/null || true
}

display_backup_info() {
    local backup_path=$1
    local backup_size=$(du -sh "$backup_path" | cut -f1)
    
    log_info "Backup completed successfully!"
    echo ""
    echo "Backup Details:"
    echo "  Location: $backup_path"
    echo "  Size: $backup_size"
    echo "  Files:"
    ls -lh "$backup_path" | tail -n +2 | while read line; do
        echo "    $line"
    done
    echo ""
    echo "To restore this backup:"
    echo "  ./scripts/restore.sh \"$backup_path\""
}

# Main execution
main() {
    local backup_base_dir=${1:-$DEFAULT_BACKUP_DIR}
    
    # Handle help flag
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        print_usage
        exit 0
    fi
    
    log_info "Starting ExplorerLLM backup process..."
    
    # Pre-flight checks
    check_dependencies
    check_services
    
    # Create backup directory
    local backup_path=$(create_backup_dir "$backup_base_dir")
    
    # Perform backup
    backup_data "$backup_path"
    
    # Cleanup old backups
    cleanup_old_backups "$backup_base_dir"
    
    # Display results
    display_backup_info "$backup_path"
    
    log_info "Backup process completed!"
}

# Run main function with all arguments
main "$@"
