#!/bin/bash

# Docker Setup Script
# This installs Docker and Docker Compose on a Debian-based system
# Usage: ./setup-docker.sh

set -e  # Exit on any error

# Functions
function log_info {
  echo "[INFO] $1"
}

function log_error {
  echo "[ERROR] $1"
  exit 1
}

function install_docker {
  log_info "Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh || log_error "Failed to download Docker installation script"
  sh get-docker.sh || log_error "Failed to install Docker"
  rm get-docker.sh
  log_info "Docker installed successfully"
}

function install_docker_compose {
  log_info "Installing Docker Compose..."
  sudo apt-get update -y || log_error "Failed to update package lists"
  sudo apt-get install -y docker-compose || log_error "Failed to install Docker Compose"
  log_info "Docker Compose installed successfully"
}

function add_user_docker_group {
  log_info "Adding user to docker group..."
  sudo usermod -aG docker $USER || log_error "Failed to add user to docker group"
  log_info "Please log out and back in to apply Docker group changes"
}

# Main
install_docker
install_docker_compose
add_user_docker_group

log_info "Docker and Docker Compose setup complete!"
