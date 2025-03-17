#!/bin/bash
set -e  # Exit immediately if any command fails

echo "=== Starting deployment process ==="

# Create the application directory
APP_DIR="/var/www/CHATBAOT"
echo "Setting up app directory at $APP_DIR"
sudo mkdir -p "$APP_DIR"
sudo chown $(whoami):$(whoami) "$APP_DIR"

# Show files to be deployed
echo "Files to be deployed:"
ls -la

# Preserve existing Gunicorn logs
if [ -f "$APP_DIR/gunicorn.log" ]; then
    echo "Preserving existing logs"
    sudo cp "$APP_DIR/gunicorn.log" /tmp/gunicorn.log.backup
fi

echo "Removing old application files..."
sudo rm -rf "$APP_DIR"/*

echo "Deploying new files..."
sudo cp -r * "$APP_DIR/"
sudo chown -R $(whoami):$(whoami) "$APP_DIR"

# Restore logs if they existed
if [ -f /tmp/gunicorn.log.backup ]; then
    echo "Restoring log file"
    sudo mv /tmp/gunicorn.log.backup "$APP_DIR/gunicorn.log"
fi

# Navigate to application directory
cd "$APP_DIR"

# Handle environment file
if [ -f env ]; then
    mv env .env
    echo "Renamed env to .env"
else
    echo "WARNING: .env file not found. Creating an empty .env file."
    touch .env
fi

# Update system and install necessary packages
echo "Updating system packages..."
sudo apt-get update -y

echo "Installing Python and dependencies..."
sudo apt-get install -y python3 python3-pip python3-dev

# Install application dependencies
if [ -f requirements.txt ]; then
    echo "Installing dependencies from requirements.txt"
    sudo pip3 install -r requirements.txt
else
    echo "WARNING: requirements.txt not found. Installing essential packages."
    sudo pip3 install streamlit==1.32.0 fastapi==0.109.2 uvicorn==0.27.1 pydantic==2.5.2 langchain==0.1.4 \
        langchain_google_genai==0.0.6 langchain_community==0.0.13 faiss-cpu==1.7.4 python-dotenv==1.0.0 \
        gunicorn==21.2.0
fi

# Ensure sample transcript exists
TRANSCRIPT_FILE="cleaned_transcript.txt"
if [ ! -f "$TRANSCRIPT_FILE" ]; then
    echo "Creating sample transcript file..."
    echo "Welcome to today's lecture on Artificial Intelligence and Machine Learning." > "$TRANSCRIPT_FILE"
    echo "This is a sample transcript file created during deployment." >> "$TRANSCRIPT_FILE"
fi

# Install and configure Nginx
if ! command -v nginx > /dev/null; then
    echo "Installing Nginx..."
    sudo apt-get install -y nginx
fi

echo "Configuring Nginx..."
NGINX_CONF="/etc/nginx/sites-available/chatbaot"
sudo tee "$NGINX_CONF" > /dev/null << 'NGINX_CONFIG'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX_CONFIG

# Enable the new Nginx configuration
sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/chatbaot
sudo rm -f /etc/nginx/sites-enabled/default

# Validate and restart Nginx
echo "Validating Nginx configuration..."
sudo nginx -t
echo "Restarting Nginx..."
sudo systemctl restart nginx

# Stop any existing Gunicorn processes
echo "Stopping any running Gunicorn processes..."
sudo pkill -f gunicorn || true

# Display directory contents
echo "Deployment directory contents:"
ls -la

# Start Gunicorn with HTTP binding
echo "Starting Gunicorn..."
cd "$APP_DIR"
nohup sudo gunicorn --workers 3 --bind 0.0.0.0:8000 app:api --timeout 120 > gunicorn.log 2>&1 &

# Allow time for Gunicorn to start
echo "Waiting for Gunicorn to initialize..."
sleep 10

# Verify application is running
echo "Checking application status..."
if curl -s http://127.0.0.1:8000/; then
    echo "Application is running successfully!"
else
    echo "WARNING: Application is not responding on port 8000."
fi

echo "=== Deployment complete ==="
echo "Check logs at: $APP_DIR/gunicorn.log"
