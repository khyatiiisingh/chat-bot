#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

echo "=== Starting deployment process ==="

# Create destination directory with proper permissions
echo "Setting up app directory"
sudo mkdir -p /var/www/langchain-app
sudo chown $(whoami):$(whoami) /var/www/langchain-app

# Show files that will be deployed
echo "Files to be deployed:"
ls -la

# Remove old app contents while preserving any logs
if [ -f /var/www/langchain-app/gunicorn.log ]; then
    echo "Preserving existing logs"
    sudo cp /var/www/langchain-app/gunicorn.log /tmp/gunicorn.log.backup
fi

echo "Removing old app contents"
sudo rm -rf /var/www/langchain-app/*

echo "Moving files to app folder"
sudo cp -r * /var/www/langchain-app/
sudo chown -R $(whoami):$(whoami) /var/www/langchain-app

# Restore logs if they existed
if [ -f /tmp/gunicorn.log.backup ]; then
    sudo mv /tmp/gunicorn.log.backup /var/www/langchain-app/gunicorn.log
fi

# Navigate to the app directory
cd /var/www/langchain-app/

# Ensure the .env file exists
if [ -f env ]; then
    sudo mv env .env
    echo ".env file created from env"
else
    echo "WARNING: env file not found, creating empty .env"
    touch .env
fi

# Update system packages
echo "Updating system packages"
sudo apt-get update

echo "Installing python and pip"
sudo apt-get install -y python3 python3-pip python3-dev

# Install application dependencies from requirements.txt
echo "Installing application dependencies from requirements.txt"
if [ -f requirements.txt ]; then
    sudo pip3 install -r requirements.txt
else
    echo "WARNING: requirements.txt not found, installing essential packages"
    sudo pip3 install streamlit langchain langchain_google_genai langchain_community faiss-cpu python-dotenv fastapi uvicorn gunicorn pydantic
fi

# Create sample transcript if not exists
if [ ! -f cleaned_transcript.txt ]; then
    echo "Creating sample transcript file"
    echo "Welcome to today's lecture on Artificial Intelligence and Machine Learning." > cleaned_transcript.txt
    echo "This is a sample transcript file created during deployment." >> cleaned_transcript.txt
fi

# Update and install Nginx if not already installed
if ! command -v nginx > /dev/null; then
    echo "Installing Nginx"
    sudo apt-get update
    sudo apt-get install -y nginx
fi

# Configure Nginx
echo "Configuring Nginx for HTTP proxy"
sudo tee /etc/nginx/sites-available/myapp > /dev/null << NGINX_CONFIG
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX_CONFIG

# Enable the site
sudo ln -sf /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled
sudo rm -f /etc/nginx/sites-enabled/default

# Validate nginx config
echo "Validating Nginx configuration"
sudo nginx -t

# Restart Nginx
echo "Restarting Nginx"
sudo systemctl restart nginx

# Stop any existing Gunicorn processes
echo "Stopping any existing Gunicorn processes"
sudo pkill gunicorn || true

# Create a minimal test app.py if needed
if [ ! -f app.py ]; then
    echo "WARNING: app.py not found, creating test version"
    sudo tee app.py > /dev/null << APP_CONTENT
from fastapi import FastAPI

api = FastAPI()

@api.get("/")
def read_root():
    return {"message": "API is running. This is a test deployment."}

@api.get("/health")
def health_check():
    return {"status": "healthy"}
APP_CONTENT
fi

echo "Directory contents:"
ls -la

# Start Gunicorn with HTTP binding
echo "Starting Gunicorn with HTTP binding"
cd /var/www/langchain-app/
nohup sudo gunicorn --workers 3 --bind 0.0.0.0:8000 app:api --timeout 120 > gunicorn.log 2>&1 &

# Give Gunicorn time to start
echo "Waiting for Gunicorn to start..."
sleep 10

# Verify the app is running
echo "Verifying application is running"
curl -s http://127.0.0.1:8000/ || echo "WARNING: Application is not responding on port 8000"

echo "=== Deployment complete ==="
echo "Check application logs at: /var/www/langchain-app/gunicorn.log"