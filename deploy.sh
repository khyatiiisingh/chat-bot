#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

echo "=== Starting deployment process ==="

# Create destination directory with proper permissions
echo "Setting up app directory"
sudo mkdir -p /var/www/CHATBAOT
sudo chown $(whoami):$(whoami) /var/www/CHATBAOT

# Show files that will be deployed
echo "Files to be deployed:"
ls -la

# Remove old app contents while preserving any logs
if [ -f /var/www/CHATBAOT/gunicorn.log ]; then
    echo "Preserving existing logs"
    sudo cp /var/www/CHATBAOT/gunicorn.log /tmp/gunicorn.log.backup
fi

echo "Removing old app contents"
sudo rm -rf /var/www/CHATBAOT/*

echo "Moving files to app folder"
sudo cp -r * /var/www/CHATBAOT/
sudo chown -R $(whoami):$(whoami) /var/www/CHATBAOT

# Restore logs if they existed
if [ -f /tmp/gunicorn.log.backup ]; then
    sudo mv /tmp/gunicorn.log.backup /var/www/CHATBAOT/gunicorn.log
fi

# Navigate to the app directory
cd /var/www/CHATBAOT/

# Ensure the .env file exists
if [ -f env ]; then
    mv env .env
    echo ".env file created from env"
else
    echo "WARNING: env file not found, creating empty .env"
    touch .env
fi

# Update system packages
echo "Updating system packages"
sudo apt-get update

echo "Installing Python and pip"
sudo apt-get install -y python3 python3-pip python3-dev

# Ensure requirements.txt exists
if [ ! -f requirements.txt ]; then
  cat > requirements.txt << 'REQUIREMENTS_EOF'
streamlit==1.32.0
fastapi==0.109.2
uvicorn==0.27.1
pydantic==2.5.2
langchain==0.1.4
langchain_google_genai==0.0.6
langchain_community==0.0.13
faiss-cpu==1.7.4
python-dotenv==1.0.0
gunicorn==21.2.0
REQUIREMENTS_EOF
fi

# Install application dependencies
echo "Installing application dependencies from requirements.txt"
sudo pip3 install -r requirements.txt

# Create sample transcript if not exists
if [ ! -f cleaned_transcript.txt ]; then
    echo "Creating sample transcript file"
    echo "Welcome to today's lecture on Artificial Intelligence and Machine Learning." > cleaned_transcript.txt
    echo "This is a sample transcript file created during deployment." >> cleaned_transcript.txt
fi

# Install and configure Nginx
if ! command -v nginx > /dev/null; then
    echo "Installing Nginx"
    sudo apt-get install -y nginx
fi

echo "Configuring Nginx for HTTP proxy"
sudo tee /etc/nginx/sites-available/chatbaot > /dev/null << 'NGINX_CONFIG'
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

# Enable the site
sudo ln -sf /etc/nginx/sites-available/chatbaot /etc/nginx/sites-enabled
sudo rm -f /etc/nginx/sites-enabled/default

# Validate Nginx config
echo "Validating Nginx configuration"
sudo nginx -t

# Restart Nginx
echo "Restarting Nginx"
sudo systemctl restart nginx

# Stop any existing Gunicorn processes
echo "Stopping any existing Gunicorn processes"
sudo pkill gunicorn || true

echo "Directory contents:"
ls -la

# Start Gunicorn
echo "Starting Gunicorn"
cd /var/www/CHATBAOT/
nohup sudo gunicorn --workers 3 --bind 0.0.0.0:8000 app:api --timeout 120 > gunicorn.log 2>&1 &

# Wait for Gunicorn to start
echo "Waiting for Gunicorn to start..."
sleep 10

# Verify the app is running
echo "Verifying application is running"
curl -s http://127.0.0.1:8000/ || echo "WARNING: Application is not responding on port 8000"

echo "=== Deployment complete ==="
echo "Check application logs at: /var/www/CHATBAOT/gunicorn.log"