#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

echo "=== Starting deployment process ==="

# Create destination directory with proper permissions
echo "Setting up app directory"
sudo mkdir -p /var/www/CHATBOT
sudo chown "$(whoami):$(whoami)" /var/www/CHATBOT

# Show files that will be deployed
echo "Files to be deployed:"
ls -la

# Remove old app contents while preserving logs
if [ -f /var/www/CHATBOT/gunicorn.log ]; then
    echo "Preserving existing logs"
    sudo cp /var/www/CHATBOT/gunicorn.log /tmp/gunicorn.log.backup
fi

echo "Removing old app contents"
sudo rm -rf /var/www/CHATBOT/*

echo "Moving files to app folder"
sudo cp -r * /var/www/CHATBOT/
sudo chown -R "$(whoami):$(whoami)" /var/www/CHATBOT

# Restore logs if they existed
if [ -f /tmp/gunicorn.log.backup ]; then
    sudo mv /tmp/gunicorn.log.backup /var/www/CHATBOT/gunicorn.log
fi

cd /var/www/CHATBOT/

# Ensure .env file exists
if [ -f env ]; then
    sudo mv env .env
    echo ".env file created from env"
else
    echo "WARNING: env file not found, creating empty .env"
    touch .env
fi

# Verify transcript files exist
if [ ! -f transcript.txt ]; then
    echo "WARNING: transcript.txt not found, creating sample file"
    echo "Welcome to today's lecture on Artificial Intelligence and Machine Learning." > transcript.txt
    echo "This is a sample transcript file created during deployment." >> transcript.txt
    echo "AI systems can analyze data, learn patterns, and make decisions." >> transcript.txt
    echo "Machine learning is a subset of AI focused on building systems that learn from data." >> transcript.txt
    echo "Deep learning uses neural networks with multiple layers." >> transcript.txt
    echo "Natural language processing allows computers to understand human language." >> transcript.txt
    echo "Sample transcript file created"
fi

# Create cleaned_transcript.txt for FastAPI app if needed
if [ ! -f cleaned_transcript.txt ]; then
    echo "Creating cleaned_transcript.txt from transcript.txt"
    cp transcript.txt cleaned_transcript.txt
fi

# Install system dependencies and Python packages
echo "Installing system dependencies and Python packages"
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-dev python3-venv python3-pillow python3-numpy python3-scipy nginx

# Create and activate Python virtual environment
echo "Creating Python virtual environment"
python3 -m venv venv
. ./venv/bin/activate

# Verify we're in the virtual environment
echo "Python interpreter being used:"
which python3

# Install Python packages in virtual environment
echo "Installing Python packages in virtual environment"
python3 -m pip install --upgrade pip setuptools wheel
python3 -m pip install -r requirements.txt

# Configure Nginx with two backends - Flask API and FastAPI
echo "Configuring Nginx"
sudo tee /etc/nginx/sites-available/chatbot > /dev/null << NGINX_EOF
server {
    listen 80;
    server_name _;
    
    # FastAPI endpoint (app.py)
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Flask API endpoint (api.py)
    location /flask/ {
        proxy_pass http://127.0.0.1:4000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX_EOF

sudo ln -sf /etc/nginx/sites-available/chatbot /etc/nginx/sites-enabled
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

# Create systemd service files for both applications
echo "Creating systemd service for FastAPI (app.py)"
sudo tee /etc/systemd/system/chatbot-fastapi.service > /dev/null << SERVICE_EOF
[Unit]
Description=CHATBOT FastAPI Service
After=network.target

[Service]
User=$(whoami)
Group=$(whoami)
WorkingDirectory=/var/www/CHATBOT
Environment="PATH=/var/www/CHATBOT/venv/bin:/usr/bin"
Environment="PYTHONPATH=/var/www/CHATBOT:/usr/lib/python3/dist-packages"
ExecStart=/var/www/CHATBOT/venv/bin/gunicorn --workers 3 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000 app:api --timeout 120
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE_EOF

echo "Creating systemd service for Flask API (api.py)"
sudo tee /etc/systemd/system/chatbot-flask.service > /dev/null << SERVICE_EOF
[Unit]
Description=CHATBOT Flask API Service
After=network.target

[Service]
User=$(whoami)
Group=$(whoami)
WorkingDirectory=/var/www/CHATBOT
Environment="PATH=/var/www/CHATBOT/venv/bin:/usr/bin"
Environment="PYTHONPATH=/var/www/CHATBOT:/usr/lib/python3/dist-packages"
ExecStart=/var/www/CHATBOT/venv/bin/gunicorn --workers 2 --bind 0.0.0.0:4000 api:app --timeout 120
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Start the applications
echo "Starting the applications as services"
sudo systemctl daemon-reload

# Start FastAPI service
sudo systemctl stop chatbot-fastapi.service || true
sudo systemctl enable chatbot-fastapi.service
sudo systemctl start chatbot-fastapi.service

# Start Flask API service
sudo systemctl stop chatbot-flask.service || true
sudo systemctl enable chatbot-flask.service
sudo systemctl start chatbot-flask.service

# Wait for the services to start
echo "Waiting for services to start..."
sleep 10

# Verify the apps are running
echo "Verifying FastAPI application is running"
curl -s http://127.0.0.1:8000/ || echo "WARNING: FastAPI application is not responding on port 8000"

echo "Verifying Flask API application is running"
curl -s http://127.0.0.1:4000/ || echo "WARNING: Flask API application is not responding on port 4000"

# Check service status
echo "FastAPI service status:"
sudo systemctl status chatbot-fastapi.service --no-pager

echo "Flask API service status:"
sudo systemctl status chatbot-flask.service --no-pager

echo "=== Deployment complete ==="
echo "Check FastAPI logs with: sudo journalctl -u chatbot-fastapi.service"
echo "Check Flask API logs with: sudo journalctl -u chatbot-flask.service"