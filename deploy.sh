#!/bin/bash
set -e

# Logging functions
log_error() {
    echo "ERROR: $1" >> /var/www/CHATBOT/deployment.log
}

log_warning() {
    echo "WARNING: $1" >> /var/www/CHATBOT/deployment.log
}

echo "=== Starting deployment process ==="

# Create destination directory with proper permissions
echo "Setting up app directory"
sudo mkdir -p /var/www/CHATBOT
sudo chown "$(whoami):$(whoami)" /var/www/CHATBOT

# Preserve logs and .env file
if [ -f /var/www/CHATBOT/gunicorn.log ]; then
    echo "Preserving existing logs"
    sudo cp /var/www/CHATBOT/gunicorn.log /tmp/gunicorn.log.backup
fi

if [ -f /var/www/CHATBOT/.env ]; then
    echo "Preserving existing .env file"
    sudo cp /var/www/CHATBOT/.env /tmp/.env.backup
fi

# Remove old app contents
echo "Removing old app contents"
sudo rm -rf /var/www/CHATBOT/*

# Move new files to app folder
echo "Moving files to app folder"
sudo cp -r * /var/www/CHATBOT/
sudo chown -R "$(whoami):$(whoami)" /var/www/CHATBOT

# Restore logs and .env file
if [ -f /tmp/gunicorn.log.backup ]; then
    sudo mv /tmp/gunicorn.log.backup /var/www/CHATBOT/gunicorn.log
fi

if [ -f /tmp/.env.backup ]; then
    echo "Merging new env with existing .env file"
    cat env /tmp/.env.backup | sort | uniq > .env
    rm env
elif [ -f env ]; then
    echo "Using new env file as .env"
    mv env .env
else
    log_warning "No env file found, creating empty .env"
    touch .env
fi

# Validate required environment variables
required_vars=("ENV" "EC2_USERNAME" "GOOGLE_API_KEY")
for var in "${required_vars[@]}"; do
    if ! grep -q "^$var=" .env; then
        log_warning "Required environment variable $var is not set in .env"
    fi
done

# Install system dependencies
echo "Installing system dependencies"
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-dev python3-venv python3-pillow python3-numpy python3-scipy nginx

# Create and activate Python virtual environment
echo "Creating Python virtual environment"
python3 -m venv venv
. ./venv/bin/activate

# Install Python packages
echo "Installing Python packages"
python3 -m pip install --upgrade pip setuptools wheel

if [ -f requirements.txt ]; then
    echo "Installing requirements from requirements.txt"
    python3 -m pip install -r requirements.txt
else
    log_warning "requirements.txt not found, installing default packages"
    python3 -m pip install flask fastapi uvicorn gunicorn python-dotenv
fi

# Configure Nginx
echo "Configuring Nginx"
sudo tee /etc/nginx/sites-available/chatbot > /dev/null << NGINX_EOF
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

# Create systemd services
echo "Creating systemd services"
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

# Start services
echo "Starting services"
sudo systemctl daemon-reload
sudo systemctl enable chatbot-fastapi.service
sudo systemctl enable chatbot-flask.service
sudo systemctl start chatbot-fastapi.service
sudo systemctl start chatbot-flask.service

# Verify services are running
is_service_running() {
    if systemctl is-active --quiet $1; then
        echo "$1 is running"
    else
        log_error "$1 is not running"
        exit 1
    fi
}

is_service_running chatbot-fastapi.service
is_service_running chatbot-flask.service

echo "=== Deployment complete ==="