#!/bin/bash

# ExplorerLLM Migration Script
# This script migrates your complete ExplorerLLM setup between servers
# Usage: ./migrate-ollama.sh <source_server> <destination_server> [options]

set -e  # Exit on any error

# Configuration
REMOTE_USER=${REMOTE_USER:-"$USER"}
REMOTE_PATH=${REMOTE_PATH:-"/home/$REMOTE_USER"}
PROJECT_NAME="explorerllm"
TEMP_DIR="/tmp/ollama_migration_$$"

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
    echo "Usage: $0 <source_server> <destination_server> [options]"
    echo ""
    echo "Arguments:"
    echo "  source_server      Source server IP or hostname"
    echo "  destination_server Destination server IP or hostname"
    echo ""
    echo "Options:"
    echo "  -u, --user USER    Remote username (default: current user)"
    echo "  -p, --path PATH    Remote path (default: /home/USER)"
    echo "  -k, --key KEY      SSH private key file"
    echo "  --dry-run          Show what would be done without executing"
    echo "  --skip-docker      Skip Docker installation on destination"
    echo "  --skip-backup      Skip creating backup on source"
    echo ""
    echo "Environment Variables:"
    echo "  REMOTE_USER        Remote username"
    echo "  REMOTE_PATH        Remote base path"
    echo "  SSH_KEY            SSH private key file"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.1.100 192.168.1.200"
    echo "  $0 old.example.com new.example.com -u admin -p /opt"
    echo "  $0 source dest --key ~/.ssh/my_key --dry-run"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--user)
                REMOTE_USER="$2"
                shift 2
                ;;
            -p|--path)
                REMOTE_PATH="$2"
                shift 2
                ;;
            -k|--key)
                SSH_KEY="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-docker)
                SKIP_DOCKER=true
                shift
                ;;
            --skip-backup)
                SKIP_BACKUP=true
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
                if [[ -z "$SOURCE_SERVER" ]]; then
                    SOURCE_SERVER="$1"
                elif [[ -z "$DEST_SERVER" ]]; then
                    DEST_SERVER="$1"
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
    if [[ -z "$SOURCE_SERVER" || -z "$DEST_SERVER" ]]; then
        log_error "Source and destination servers are required"
        print_usage
        exit 1
    fi
    
    if [[ "$SOURCE_SERVER" == "$DEST_SERVER" ]]; then
        log_error "Source and destination servers cannot be the same"
        exit 1
    fi
}

setup_ssh_options() {
    SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    
    if [[ -n "$SSH_KEY" ]]; then
        SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
    fi
}

check_connectivity() {
    log_step "Checking connectivity to servers..."
    
    if ! ssh $SSH_OPTS $REMOTE_USER@$SOURCE_SERVER "echo 'Source server connected'" 2>/dev/null; then
        log_error "Cannot connect to source server: $SOURCE_SERVER"
        exit 1
    fi
    
    if ! ssh $SSH_OPTS $REMOTE_USER@$DEST_SERVER "echo 'Destination server connected'" 2>/dev/null; then
        log_error "Cannot connect to destination server: $DEST_SERVER"
        exit 1
    fi
    
    log_info "Connectivity check passed"
}

check_source_installation() {
    log_step "Checking ExplorerLLM installation on source server..."
    
    # Check if docker-compose.yml exists
    if ! ssh $SSH_OPTS $REMOTE_USER@$SOURCE_SERVER "test -f $REMOTE_PATH/docker-compose.yml" 2>/dev/null; then
        log_error "No docker-compose.yml found on source server at $REMOTE_PATH"
        log_error "Please ensure ExplorerLLM is properly installed on the source server"
        exit 1
    fi
    
    # Check if services are running
    if ssh $SSH_OPTS $REMOTE_USER@$SOURCE_SERVER "cd $REMOTE_PATH && docker-compose ps | grep -q Up" 2>/dev/null; then
        log_info "ExplorerLLM services are running on source server"
        SOURCE_RUNNING=true
    else
        log_warn "ExplorerLLM services are not running on source server"
        SOURCE_RUNNING=false
    fi
}

install_docker_on_destination() {
    if [[ "$SKIP_DOCKER" == true ]]; then
        log_info "Skipping Docker installation (--skip-docker specified)"
        return
    fi
    
    log_step "Installing Docker on destination server..."
    
    # Check if Docker is already installed
    if ssh $SSH_OPTS $REMOTE_USER@$DEST_SERVER "command -v docker" >/dev/null 2>&1; then
        log_info "Docker is already installed on destination server"
        return
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would install Docker on destination server"
        return
    fi
    
    # Install Docker
    ssh $SSH_OPTS $REMOTE_USER@$DEST_SERVER "
        curl -fsSL https://get.docker.com -o get-docker.sh &&
        sudo sh get-docker.sh &&
        sudo usermod -aG docker $REMOTE_USER &&
        sudo apt-get update &&
        sudo apt-get install -y docker-compose
    "
    
    log_info "Docker installation completed"
    log_warn "The remote user may need to log out and back in for Docker permissions to take effect"
}

create_backup_on_source() {
    if [[ "$SKIP_BACKUP" == true ]]; then
        log_info "Skipping backup creation (--skip-backup specified)"
        return
    fi
    
    log_step "Creating backup on source server..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create backup on source server"
        return
    fi
    
    # Create backup directory
    ssh $SSH_OPTS $REMOTE_USER@$SOURCE_SERVER "mkdir -p $REMOTE_PATH/migration_backup"
    
    # Stop services if running
    if [[ "$SOURCE_RUNNING" == true ]]; then
        log_info "Stopping services on source server..."
        ssh $SSH_OPTS $REMOTE_USER@$SOURCE_SERVER "cd $REMOTE_PATH && docker-compose stop"
    fi
    
    # Create backups
    log_info "Backing up WebUI data..."
    ssh $SSH_OPTS $REMOTE_USER@$SOURCE_SERVER "
        cd $REMOTE_PATH &&
        docker run --rm -v \$(basename \$(pwd))_ollama_webui_data:/data -v \$(pwd)/migration_backup:/backup ubuntu tar czf /backup/webui-data.tar.gz /data
    "
    
    log_info "Backing up Ollama models..."
    ssh $SSH_OPTS $REMOTE_USER@$SOURCE_SERVER "
        cd $REMOTE_PATH &&
        docker run --rm -v \$(basename \$(pwd))_ollama_data:/data -v \$(pwd)/migration_backup:/backup ubuntu tar czf /backup/models.tar.gz /data
    "
    
    # Backup configuration
    ssh $SSH_OPTS $REMOTE_USER@$SOURCE_SERVER "
        cd $REMOTE_PATH &&
        cp docker-compose.yml migration_backup/
    "
    
    # Restart services if they were running
    if [[ "$SOURCE_RUNNING" == true ]]; then
        log_info "Restarting services on source server..."
        ssh $SSH_OPTS $REMOTE_USER@$SOURCE_SERVER "cd $REMOTE_PATH && docker-compose start"
    fi
    
    log_info "Backup created successfully on source server"
}

transfer_data() {
    log_step "Transferring data from source to destination..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would transfer backup files to destination server"
        return
    fi
    
    # Create project directory on destination
    ssh $SSH_OPTS $REMOTE_USER@$DEST_SERVER "mkdir -p $REMOTE_PATH/$PROJECT_NAME"
    
    # Transfer files using rsync through SSH
    log_info "Transferring backup files..."
    rsync -avz -e "ssh $SSH_OPTS" \
        $REMOTE_USER@$SOURCE_SERVER:$REMOTE_PATH/migration_backup/ \
        $REMOTE_USER@$DEST_SERVER:$REMOTE_PATH/$PROJECT_NAME/
    
    log_info "Data transfer completed"
}

restore_on_destination() {
    log_step "Restoring ExplorerLLM on destination server..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would restore ExplorerLLM on destination server"
        return
    fi
    
    # Setup on destination server
    ssh $SSH_OPTS $REMOTE_USER@$DEST_SERVER "
        cd $REMOTE_PATH/$PROJECT_NAME &&
        
        # Create volumes first
        docker-compose up --no-start &&
        
        # Restore WebUI data
        docker run --rm -v ${PROJECT_NAME}_ollama_webui_data:/data -v \$(pwd):/backup ubuntu tar xzf /backup/webui-data.tar.gz -C / &&
        
        # Restore models
        docker run --rm -v ${PROJECT_NAME}_ollama_data:/data -v \$(pwd):/backup ubuntu tar xzf /backup/models.tar.gz -C / &&
        
        # Start services
        docker-compose up -d
    "
    
    log_info "Restoration completed on destination server"
}

verify_migration() {
    log_step "Verifying migration..."
    
    # Check if services are running on destination
    if ssh $SSH_OPTS $REMOTE_USER@$DEST_SERVER "cd $REMOTE_PATH/$PROJECT_NAME && docker-compose ps | grep -q Up" 2>/dev/null; then
        log_info "✅ Services are running on destination server"
    else
        log_error "❌ Services are not running on destination server"
        return 1
    fi
    
    # Check if models are available
    local model_count=$(ssh $SSH_OPTS $REMOTE_USER@$DEST_SERVER "cd $REMOTE_PATH/$PROJECT_NAME && docker exec \$(docker-compose ps -q ollama) ollama list 2>/dev/null | wc -l" || echo "0")
    if [[ "$model_count" -gt 1 ]]; then
        log_info "✅ Models are available on destination server ($((model_count-1)) models)"
    else
        log_warn "⚠️  No models found on destination server"
    fi
    
    log_info "Migration verification completed"
}

cleanup() {
    log_step "Cleaning up temporary files..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would clean up temporary files"
        return
    fi
    
    # Cleanup on source server
    ssh $SSH_OPTS $REMOTE_USER@$SOURCE_SERVER "rm -rf $REMOTE_PATH/migration_backup" 2>/dev/null || true
    
    # Cleanup backup files on destination (keep docker-compose.yml)
    ssh $SSH_OPTS $REMOTE_USER@$DEST_SERVER "cd $REMOTE_PATH/$PROJECT_NAME && rm -f *.tar.gz" 2>/dev/null || true
    
    log_info "Cleanup completed"
}

print_summary() {
    echo ""
    echo "🎉 Migration Summary"
    echo "==================="
    echo "Source Server: $SOURCE_SERVER"
    echo "Destination Server: $DEST_SERVER"
    echo "Destination Path: $REMOTE_PATH/$PROJECT_NAME"
    echo ""
    echo "Next steps:"
    echo "1. Access the WebUI at: http://$DEST_SERVER:3000"
    echo "2. Verify your data and models are intact"
    echo "3. Update DNS/load balancer to point to new server"
    echo "4. Consider stopping services on the old server"
    echo ""
    echo "To stop services on the old server:"
    echo "  ssh $REMOTE_USER@$SOURCE_SERVER 'cd $REMOTE_PATH && docker-compose stop'"
}

# Main execution
main() {
    parse_arguments "$@"
    validate_arguments
    setup_ssh_options
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warn "DRY RUN MODE - No actual changes will be made"
        echo ""
    fi
    
    log_info "Starting ExplorerLLM migration..."
    log_info "Source: $SOURCE_SERVER"
    log_info "Destination: $DEST_SERVER"
    echo ""
    
    # Execute migration steps
    check_connectivity
    check_source_installation
    install_docker_on_destination
    create_backup_on_source
    transfer_data
    restore_on_destination
    verify_migration
    cleanup
    
    if [[ "$DRY_RUN" != true ]]; then
        print_summary
    fi
    
    log_info "Migration completed successfully! 🚀"
}

# Trap for cleanup on exit
trap 'log_warn "Migration interrupted. You may need to manually clean up temporary files."' EXIT

# Run main function with all arguments
main "$@"

# Remove trap on successful completion
trap - EXIT
