#!/bin/bash

# ExplorerLLM Restore Script
# This script restores ExplorerLLM from a backup
# Usage: ./restore.sh <backup_directory>

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_usage() {
    echo "Usage: $0 <backup_directory> [options]"
    echo ""
    echo "Arguments:"
    echo "  backup_directory   Path to the backup directory containing ExplorerLLM backup"
    echo ""
    echo "Options:"
    echo "  --force           Force restore even if services are running"
    echo "  --dry-run         Show what would be done without executing"
    echo "  --skip-config     Skip restoring docker-compose.yml"
    echo ""
    echo "Examples:"
    echo "  $0 /backups/explorerllm_20240104_142000"
    echo "  $0 ./backup --force"
    echo "  $0 /path/to/backup --dry-run"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_RESTORE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-config)
                SKIP_CONFIG=true
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
            *)
                if [[ -z "$BACKUP_DIR" ]]; then
                    BACKUP_DIR="$1"
                else
                    log_error "Too many arguments"
                    print_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

validate_arguments() {
    if [[ -z "$BACKUP_DIR" ]]; then
        log_error "Backup directory is required"
        print_usage
        exit 1
    fi
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "Backup directory does not exist: $BACKUP_DIR"
        exit 1
    fi
}

validate_backup() {
    log_step "Validating backup directory..."
    
    local required_files=()
    local webui_backup=""
    local models_backup=""
    local config_backup=""
    
    # Find backup files (they may have timestamps)
    for file in "$BACKUP_DIR"/*.tar.gz; do
        if [[ -f "$file" ]]; then
            local basename=$(basename "$file")
            if [[ "$basename" == *"webui"* ]]; then
                webui_backup="$file"
            elif [[ "$basename" == *"models"* ]]; then
                models_backup="$file"
            fi
        fi
    done
    
    # Check for config file
    if [[ -f "$BACKUP_DIR/docker-compose.yml" ]]; then
        config_backup="$BACKUP_DIR/docker-compose.yml"
    fi
    
    # Validate required files
    if [[ -z "$webui_backup" ]]; then
        log_error "WebUI backup file not found in $BACKUP_DIR"
        log_error "Expected a file containing 'webui' in the name"
        exit 1
    fi
    
    if [[ -z "$models_backup" ]]; then
        log_error "Models backup file not found in $BACKUP_DIR"
        log_error "Expected a file containing 'models' in the name"
        exit 1
    fi
    
    if [[ -z "$config_backup" && "$SKIP_CONFIG" != true ]]; then
        log_warn "docker-compose.yml not found in backup directory"
        log_warn "Use --skip-config if you want to use existing configuration"
    fi
    
    # Store found files for later use
    WEBUI_BACKUP="$webui_backup"
    MODELS_BACKUP="$models_backup"
    CONFIG_BACKUP="$config_backup"
    
    log_info "Backup validation passed"
    log_info "WebUI backup: $(basename "$WEBUI_BACKUP")"
    log_info "Models backup: $(basename "$MODELS_BACKUP")"
    if [[ -n "$CONFIG_BACKUP" ]]; then
        log_info "Config backup: $(basename "$CONFIG_BACKUP")"
    fi
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

check_current_installation() {
    log_step "Checking current installation..."
    
    if [[ ! -f "docker-compose.yml" && -z "$CONFIG_BACKUP" ]]; then
        log_error "No docker-compose.yml found in current directory and no config in backup"
        log_error "Either restore from a directory with docker-compose.yml or ensure backup contains config"
        exit 1
    fi
    
    # Check if services are running
    if docker-compose ps 2>/dev/null | grep -q "Up"; then
        if [[ "$FORCE_RESTORE" != true ]]; then
            log_error "ExplorerLLM services are currently running"
            log_error "Stop services first or use --force to automatically stop them"
            log_error "To stop: docker-compose stop"
            exit 1
        else
            log_warn "Services are running but --force specified, will stop them"
            SERVICES_RUNNING=true
        fi
    else
        SERVICES_RUNNING=false
    fi
}

stop_services() {
    if [[ "$SERVICES_RUNNING" == true ]]; then
        log_step "Stopping services..."
        
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would stop services"
            return
        fi
        
        docker-compose stop
        log_info "Services stopped"
    fi
}

restore_configuration() {
    if [[ "$SKIP_CONFIG" == true || -z "$CONFIG_BACKUP" ]]; then
        log_info "Skipping configuration restore"
        return
    fi
    
    log_step "Restoring configuration..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would restore docker-compose.yml"
        return
    fi
    
    # Backup current config if it exists
    if [[ -f "docker-compose.yml" ]]; then
        cp docker-compose.yml "docker-compose.yml.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Current configuration backed up"
    fi
    
    # Restore config
    cp "$CONFIG_BACKUP" docker-compose.yml
    log_info "Configuration restored"
}

restore_data() {
    log_step "Restoring data volumes..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would restore WebUI and model data"
        return
    fi
    
    local project_dir=$(pwd)
    local project_name=${project_dir##*/}
    
    # Create volumes if they don't exist
    log_info "Creating Docker volumes..."
    docker-compose up --no-start
    
    # Restore WebUI data
    log_info "Restoring WebUI data..."
    docker run --rm \
        -v "${project_name}_ollama_webui_data:/data" \
        -v "$(dirname "$WEBUI_BACKUP"):/backup" \
        ubuntu:latest \
        tar xzf "/backup/$(basename "$WEBUI_BACKUP")" -C /
    
    # Restore Ollama models
    log_info "Restoring Ollama models..."
    docker run --rm \
        -v "${project_name}_ollama_data:/data" \
        -v "$(dirname "$MODELS_BACKUP"):/backup" \
        ubuntu:latest \
        tar xzf "/backup/$(basename "$MODELS_BACKUP")" -C /
    
    log_info "Data restoration completed"
}

start_services() {
    log_step "Starting services..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would start services"
        return
    fi
    
    docker-compose up -d
    
    # Wait for services to be ready
    log_info "Waiting for services to start..."
    sleep 15
    
    # Verify services are running
    if docker-compose ps | grep -q "Up"; then
        log_info "Services started successfully"
    else
        log_warn "Services may not be running properly"
        log_warn "Check status with: docker-compose ps"
        log_warn "Check logs with: docker-compose logs"
    fi
}

verify_restore() {
    log_step "Verifying restore..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would verify restore"
        return
    fi
    
    # Check if services are running
    if docker-compose ps | grep -q "Up"; then
        log_info "✅ Services are running"
    else
        log_error "❌ Services are not running"
        return 1
    fi
    
    # Check if Ollama is responding
    if docker exec "$(docker-compose ps -q ollama)" ollama list >/dev/null 2>&1; then
        local model_count=$(docker exec "$(docker-compose ps -q ollama)" ollama list 2>/dev/null | wc -l)
        if [[ "$model_count" -gt 1 ]]; then
            log_info "✅ Ollama is responding with $((model_count-1)) models"
        else
            log_warn "⚠️  Ollama is responding but no models found"
        fi
    else
        log_warn "⚠️  Cannot verify Ollama status"
    fi
    
    log_info "Restore verification completed"
}

print_summary() {
    echo ""
    echo "🎉 Restore Summary"
    echo "=================="
    echo "Backup Source: $BACKUP_DIR"
    echo "Project Directory: $(pwd)"
    echo ""
    echo "Restored:"
    echo "- WebUI data (users, chat history, settings)"
    echo "- Ollama models"
    if [[ "$SKIP_CONFIG" != true && -n "$CONFIG_BACKUP" ]]; then
        echo "- Docker Compose configuration"
    fi
    echo ""
    echo "Next steps:"
    echo "1. Access the WebUI at: http://localhost:3000"
    echo "2. Verify your data and models are intact"
    echo "3. Check that all expected users and conversations are present"
    echo ""
    echo "If you encounter issues:"
    echo "  docker-compose ps      # Check service status"
    echo "  docker-compose logs    # Check logs"
    echo "  docker exec ollama ollama list  # Check models"
}

# Main execution
main() {
    parse_arguments "$@"
    validate_arguments
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warn "DRY RUN MODE - No actual changes will be made"
        echo ""
    fi
    
    log_info "Starting ExplorerLLM restore process..."
    log_info "Backup source: $BACKUP_DIR"
    echo ""
    
    # Execute restore steps
    validate_backup
    check_dependencies
    check_current_installation
    stop_services
    restore_configuration
    restore_data
    start_services
    verify_restore
    
    if [[ "$DRY_RUN" != true ]]; then
        print_summary
    fi
    
    log_info "Restore completed successfully! 🚀"
}

# Run main function with all arguments
main "$@"
