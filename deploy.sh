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

# Remove old app contents while preserving logs
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

cd /var/www/CHATBAOT/

# Ensure .env file exists
if [ -f env ]; then
    sudo mv env .env
    echo ".env file created from env"
else
    echo "WARNING: env file not found, creating empty .env"
    touch .env
fi

# Install dependencies
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-dev nginx

if [ -f requirements.txt ]; then
    sudo pip3 install -r requirements.txt
else
    echo "WARNING: requirements.txt not found, installing essential packages"
    sudo pip3 install streamlit fastapi uvicorn pydantic langchain langchain_google_genai langchain_community faiss-cpu python-dotenv gunicorn
fi

# Configure and restart Nginx
# Using a temporary file approach instead of here-document
cat > /tmp/nginx_config << EOF
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
EOF
sudo cp /tmp/nginx_config /etc/nginx/sites-available/chatbaot
rm /tmp/nginx_config

sudo ln -sf /etc/nginx/sites-available/chatbaot /etc/nginx/sites-enabled
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

# Start the application
sudo pkill gunicorn || true
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
echo "Check logs at: /var/www/CHATBAOT/gunicorn.log"