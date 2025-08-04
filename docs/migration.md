# Migration Guide

This guide covers moving your ExplorerLLM setup between servers, backing up data, and scaling to production.

## Quick Migration

For moving between similar environments (both with Docker), use the provided migration script:

```bash
chmod +x scripts/migrate-ollama.sh
./scripts/migrate-ollama.sh old-server-ip new-server-ip
```

## Manual Migration Process

### Step 1: Backup Current Installation

On your source server:

```bash
# Create backup directory
mkdir -p backups

# Stop services gracefully
docker-compose stop

# Backup WebUI data (users, chat history, settings)
docker run --rm -v ollama-chat_ollama_webui_data:/data -v $(pwd)/backups:/backup ubuntu tar czf /backup/webui-data.tar.gz /data

# Backup models
docker run --rm -v ollama-chat_ollama_data:/data -v $(pwd)/backups:/backup ubuntu tar czf /backup/models.tar.gz /data

# Backup configuration
cp docker-compose.yml backups/

# Verify backups
ls -lh backups/
```

### Step 2: Transfer Files

```bash
# Transfer to new server
scp backups/webui-data.tar.gz user@new-server:/home/user/
scp backups/models.tar.gz user@new-server:/home/user/
scp backups/docker-compose.yml user@new-server:/home/user/
```

### Step 3: Restore on New Server

On your destination server:

```bash
# Install Docker (if not already installed)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
sudo apt install docker-compose -y

# Create project directory
mkdir ollama-chat && cd ollama-chat

# Copy configuration
cp ~/docker-compose.yml .

# Create volumes first
docker-compose up --no-start

# Restore WebUI data
docker run --rm -v ollama-chat_ollama_webui_data:/data -v ~/:/backup ubuntu tar xzf /backup/webui-data.tar.gz -C /

# Restore models
docker run --rm -v ollama-chat_ollama_data:/data -v ~/:/backup ubuntu tar xzf /backup/models.tar.gz -C /

# Start services
docker-compose up -d

# Verify everything works
docker-compose ps
```

## Production Deployment Considerations

### Security Hardening

1. **Change default secret key**:
   ```yaml
   environment:
     - WEBUI_SECRET_KEY=$(openssl rand -base64 32)
   ```

2. **Use reverse proxy** (nginx/traefik):
   ```yaml
   # Remove direct port exposure
   # ports:
   #   - "3000:8080"
   ```

3. **Enable HTTPS**:
   ```bash
   # Example with Let's Encrypt
   certbot --nginx -d explorerllm.com
   ```

### Resource Planning

| Users | RAM | CPU | Storage |
|-------|-----|-----|---------|
| 1-5   | 8GB | 2 cores | 50GB |
| 5-20  | 16GB | 4 cores | 100GB |
| 20-50 | 32GB | 8 cores | 200GB |
| 50+   | 64GB+ | 16+ cores | 500GB+ |

### Backup Strategy

#### Automated Daily Backups

Create a backup script:

```bash
#!/bin/bash
# Save as scripts/backup.sh

BACKUP_DIR="/backups/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Stop services
docker-compose stop

# Backup data
docker run --rm -v ollama-chat_ollama_webui_data:/data -v $BACKUP_DIR:/backup ubuntu tar czf /backup/webui-$(date +%Y%m%d).tar.gz /data
docker run --rm -v ollama-chat_ollama_data:/data -v $BACKUP_DIR:/backup ubuntu tar czf /backup/models-$(date +%Y%m%d).tar.gz /data

# Restart services
docker-compose start

# Clean old backups (keep 30 days)
find /backups -name "*.tar.gz" -mtime +30 -delete
```

Add to crontab:
```bash
# Daily backup at 2 AM
0 2 * * * /path/to/scripts/backup.sh
```

## Educational Institution Deployment

### Multi-Course Setup

Create separate instances per course:

```bash
# Course-specific directories
mkdir -p courses/{cs101,cs201,math150}

# Each with their own compose file
cp docker-compose.yml courses/cs101/docker-compose-cs101.yml

# Modify ports and volume names
sed -i 's/3000/3001/g' courses/cs101/docker-compose-cs101.yml
sed -i 's/ollama_/cs101_ollama_/g' courses/cs101/docker-compose-cs101.yml
```

### Central Model Repository

Share models between courses to save disk space:

```yaml
# In each course's docker-compose.yml
volumes:
  - shared_models:/root/.ollama  # Shared across all courses
  - cs101_webui_data:/app/backend/data  # Course-specific data
```

### Student Data Management

Consider GDPR/FERPA compliance:

1. **Data anonymization**: Remove personally identifiable information
2. **Retention policies**: Automatically delete old conversations
3. **Export capabilities**: Allow students to download their data
4. **Access controls**: Separate admin and student interfaces

## Scaling and Performance

### Horizontal Scaling

For high-traffic deployments:

```yaml
# docker-compose.yml
services:
  ollama:
    deploy:
      replicas: 3
  
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
```

### Model Optimization

1. **Use quantized models**: Smaller, faster models (Q4, Q8)
2. **Model switching**: Load different models based on use case
3. **Caching**: Implement response caching for common queries

## Troubleshooting Migration Issues

### Volume Permission Problems

```bash
# Fix volume permissions
docker run --rm -v ollama_data:/data ubuntu chown -R 1000:1000 /data
```

### Port Conflicts

```bash
# Check what's using your ports
sudo netstat -tulpn | grep :3000
sudo lsof -i :3000
```

### Model Corruption

```bash
# Re-download corrupted models
docker exec ollama ollama rm model-name
docker exec ollama ollama pull model-name
```

## Next Steps

- [Educational Implementation](educational-use.md) - Course-specific configurations
- [Setup Guide](setup.md) - Return to basic setup
- Check migration scripts in the [scripts](../scripts/) directory
