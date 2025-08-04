# Setup Guide

This guide will walk you through setting up ExplorerLLM on your local machine or server.

## Prerequisites

- Docker and Docker Compose
- At least 4GB RAM (8GB+ recommended)
- 10GB+ free disk space for models

## Installation

### Step 1: Install Docker

#### On Ubuntu/Debian (WSL included):

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt install docker-compose -y

# Logout and back in for Docker permissions to take effect
```

#### On Windows:
Download and install Docker Desktop from [docker.com](https://www.docker.com/products/docker-desktop/)

#### On macOS:
Download and install Docker Desktop from [docker.com](https://www.docker.com/products/docker-desktop/)

### Step 2: Clone and Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/explorerllm.git
cd explorerllm

# Start the services
docker-compose up -d

# Check if services are running
docker-compose ps
```

### Step 3: Download Models

```bash
# Download a lightweight model for testing
docker exec ollama ollama pull qwen2:0.5b

# For better performance, try larger models:
docker exec ollama ollama pull llama3.1:8b
docker exec ollama ollama pull qwen2:7b

# Check available models
docker exec ollama ollama list
```

### Step 4: Access the Interface

Open your browser and navigate to:
```
http://localhost:3000
```

Create an account and start chatting!

## Configuration

### Changing the Secret Key

1. Edit `docker-compose.yml`
2. Change `WEBUI_SECRET_KEY=your-secret-key-change-this` to a secure random string
3. Restart services: `docker-compose restart`

### GPU Support (NVIDIA)

If you have an NVIDIA GPU:

1. Install [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
2. Uncomment the GPU section in `docker-compose.yml`
3. Restart services: `docker-compose restart`

### Port Configuration

Default ports:
- **WebUI**: 3000 (http://localhost:3000)
- **Ollama API**: 11434

To change ports, edit the `ports` section in `docker-compose.yml`:
```yaml
ports:
  - "8080:8080"  # Changes WebUI to port 8080
```

## Daily Operations

### Starting/Stopping Services

```bash
# Start services
docker-compose start

# Stop services (preserves data)
docker-compose stop

# Restart services
docker-compose restart

# View logs
docker-compose logs -f ollama-webui
```

### Model Management

```bash
# List available models online
docker exec ollama ollama list

# Pull a new model
docker exec ollama ollama pull model-name:tag

# Remove a model
docker exec ollama ollama rm model-name:tag
```

### Data Persistence

Your data is stored in Docker volumes:
- `ollama_data` - Downloaded models
- `ollama_webui_data` - Chat history, user accounts, settings

These volumes persist even when containers are stopped or recreated.

## Troubleshooting

### Services won't start
```bash
# Check Docker is running
docker --version
docker-compose --version

# Check for port conflicts
netstat -tulpn | grep :3000
netstat -tulpn | grep :11434
```

### Models fail to download
```bash
# Check Ollama logs
docker-compose logs ollama

# Manually test Ollama
docker exec -it ollama ollama --version
```

### WebUI won't load
```bash
# Check WebUI logs
docker-compose logs ollama-webui

# Restart just the WebUI
docker-compose restart ollama-webui
```

### Performance Issues

1. **Insufficient RAM**: Close other applications or upgrade RAM
2. **Slow model responses**: Try smaller models like `qwen2:0.5b`
3. **Disk space**: Check available space with `df -h`

## Next Steps

- [Educational Implementation](educational-use.md) - Setting up for classroom use
- [Migration Guide](migration.md) - Moving to production servers
- Check the [examples](../examples/) folder for sample configurations
