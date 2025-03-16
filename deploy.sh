#!/bin/bash
echo "=== Starting deployment process ==="

echo "Deleting old app"
sudo rm -rf /var/www/langchain-app

echo "Creating app folder"
sudo mkdir -p /var/www/langchain-app

echo "Moving files to app folder"
sudo cp -r * /var/www/langchain-app/

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

# Configure Nginx to use HTTP instead of Unix socket
echo "Configuring Nginx for HTTP proxy"
sudo bash -c 'cat > /etc/nginx/sites-available/myapp <<EOF
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
EOF'

# Enable the site
sudo ln -sf /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled
sudo rm -f /etc/nginx/sites-enabled/default

# Restart Nginx
echo "Restarting Nginx"
sudo systemctl restart nginx

# Stop any existing Gunicorn processes
echo "Stopping any existing Gunicorn processes"
sudo pkill gunicorn || true

# Create a simplified test FastAPI app to verify setup
echo "Creating a test app.py if needed"
if [ ! -f app.py ]; then
    echo "WARNING: app.py not found, creating test version"
    cat > app.py <<EOF
from fastapi import FastAPI

api = FastAPI()

@api.get("/")
def read_root():
    return {"message": "API is running. This is a test deployment."}

@api.get("/health")
def health_check():
    return {"status": "healthy"}
EOF
fi

# Start Gunicorn with HTTP binding (not Unix socket)
echo "Starting Gunicorn with HTTP binding"
cd /var/www/langchain-app/
nohup sudo gunicorn --workers 3 --bind 0.0.0.0:8000 app:api --timeout 120 > gunicorn.log 2>&1 &

# Give Gunicorn time to start
echo "Waiting for Gunicorn to start..."
sleep 5

# Verify the app is running
echo "Verifying application is running"
curl -s http://127.0.0.1:8000/ || echo "WARNING: Application is not responding on port 8000"

echo "=== Deployment complete ==="
echo "Check application logs at: /var/www/langchain-app/gunicorn.log"