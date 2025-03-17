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

# Install system dependencies
echo "Installing system dependencies"
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-dev python3-venv python3-full nginx

# Install additional system dependencies needed for Pillow and FAISS
echo "Installing additional dependencies for Python packages"
sudo apt-get install -y \
    libjpeg-dev \
    zlib1g-dev \
    libpng-dev \
    libfreetype6-dev \
    libopenblas-dev \
    libblas-dev \
    liblapack-dev \
    gfortran \
    python3-pillow

# Create and activate virtual environment
echo "Setting up Python virtual environment"
python3 -m venv venv
source venv/bin/activate

# Upgrade pip and setuptools
echo "Upgrading pip and setuptools"
pip install --upgrade pip setuptools wheel

# Install specific packages first using system packages if possible
echo "Installing specific packages first"
pip install --no-cache-dir streamlit fastapi uvicorn pydantic gunicorn python-dotenv

# Try to install problematic packages with alternatives
echo "Trying to install potentially problematic packages"
pip install --no-cache-dir --only-binary=:all: faiss-cpu || {
    echo "Installing FAISS from source (this may take a while)"
    CFLAGS="-mavx2" pip install --no-cache-dir faiss-cpu
}

# Try using system pillow or install a specific version
pip install --no-cache-dir pillow==9.5.0 || {
    echo "Installing Pillow alternative"
    pip install --no-cache-dir pillow --global-option="build_ext" --global-option="--disable-jpeg"
}

# Now install langchain packages
echo "Installing LangChain packages"
pip install --no-cache-dir langchain==0.1.4
pip install --no-cache-dir langchain_google_genai==0.0.6
pip install --no-cache-dir langchain_community==0.0.13

# Configure and restart Nginx
echo "Configuring Nginx"
cat > /tmp/nginx_config << NGINX_EOF
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
NGINX_EOF
sudo cp /tmp/nginx_config /etc/nginx/sites-available/chatbaot
rm /tmp/nginx_config

sudo ln -sf /etc/nginx/sites-available/chatbaot /etc/nginx/sites-enabled
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

# Create a systemd service file for the application
echo "Creating systemd service for CHATBAOT"
cat > /tmp/chatbaot.service << SERVICE_EOF
[Unit]
Description=CHATBAOT Gunicorn Service
After=network.target

[Service]
User=$(whoami)
Group=$(whoami)
WorkingDirectory=/var/www/CHATBAOT
Environment="PATH=/var/www/CHATBAOT/venv/bin"
ExecStart=/var/www/CHATBAOT/venv/bin/gunicorn --workers 3 --bind 0.0.0.0:8000 app:api --timeout 120
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE_EOF
sudo cp /tmp/chatbaot.service /etc/systemd/system/
rm /tmp/chatbaot.service

# Start the application
echo "Starting the application as a service"
sudo systemctl daemon-reload
sudo systemctl stop chatbaot.service || true
sudo systemctl enable chatbaot.service
sudo systemctl start chatbaot.service

# Wait for the service to start
echo "Waiting for the service to start..."
sleep 10

# Verify the app is running
echo "Verifying application is running"
curl -s http://127.0.0.1:8000/ || echo "WARNING: Application is not responding on port 8000"

# Check service status
sudo systemctl status chatbaot.service --no-pager

echo "=== Deployment complete ==="
echo "Check logs with: sudo journalctl -u chatbaot.service"