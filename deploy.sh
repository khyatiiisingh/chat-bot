#!/bin/bash
set -e  # Exit on any error

# Logging functions
LOG_FILE="/var/www/CHATBOT/deployment.log"

log_error() {
    echo "ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log_warning() {
    echo "WARNING: $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo "INFO: $1" | tee -a "$LOG_FILE"
}

echo "=== Starting deployment process ==="

# Create app directory with correct permissions
log_info "Setting up app directory"
sudo mkdir -p /var/www/CHATBOT
sudo chown "$(whoami):$(whoami)" /var/www/CHATBOT

# Preserve logs and .env file
if [ -f /var/www/CHATBOT/gunicorn.log ]; then
    log_info "Preserving existing logs"
    sudo cp /var/www/CHATBOT/gunicorn.log /tmp/gunicorn.log.backup
fi

if [ -f /var/www/CHATBOT/.env ]; then
    log_info "Preserving existing .env file"
    sudo cp /var/www/CHATBOT/.env /tmp/.env.backup
fi

# Remove old application files
log_info "Removing old app contents"
sudo rm -rf /var/www/CHATBOT/*

# Move new files to application directory
log_info "Moving new files to app directory"
sudo cp -r * /var/www/CHATBOT/
sudo chown -R "$(whoami):$(whoami)" /var/www/CHATBOT

# Restore logs
if [ -f /tmp/gunicorn.log.backup ]; then
    sudo mv /tmp/gunicorn.log.backup /var/www/CHATBOT/gunicorn.log
fi

# Restore or merge .env file
cd /var/www/CHATBOT || exit 1
if [ -f /tmp/.env.backup ]; then
    log_info "Merging new env with existing .env file"
    cat env /tmp/.env.backup | sort | uniq > .env
    rm -f env
elif [ -f env ]; then
    log_info "Using new env file as .env"
    mv env .env
else
    log_warning "No .env file found, creating empty .env"
    touch .env
fi

# Validate required environment variables
required_vars=("ENV" "EC2_USERNAME" "GOOGLE_API_KEY")
for var in "${required_vars[@]}"; do
    if ! grep -q "^$var=" .env; then
        log_warning "Required environment variable $var is missing in .env"
    fi
done

# Install system dependencies
log_info "Installing system dependencies"
sudo apt-get update && sudo apt-get install -y \
    python3 python3-pip python3-dev python3-venv python3-pillow python3-numpy python3-scipy nginx

# Setup Python Virtual Environment
log_info "Creating and activating Python virtual environment"
python3 -m venv venv
source venv/bin/activate

# Install Python packages
log_info "Installing Python packages"
pip install --upgrade pip setuptools wheel

if [ -f requirements.txt ]; then
    log_info "Installing dependencies from requirements.txt"
    pip install -r requirements.txt
else
    log_warning "requirements.txt not found, installing default packages"
    pip install flask fastapi uvicorn gunicorn python-dotenv
fi

# Configure Nginx
log_info "Configuring Nginx"
sudo tee /etc/nginx/sites-available/chatbot > /dev/null << NGINX_CONF
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
NGINX_CONF

sudo ln -sf /etc/nginx/sites-available/chatbot /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx

# Create systemd service for FastAPI
log_info "Creating FastAPI service"
sudo tee /etc/systemd/system/chatbot-fastapi.service > /dev/null << FASTAPI_SERVICE
[Unit]
Description=CHATBOT FastAPI Service
After=network.target

[Service]
User=$(whoami)
Group=$(whoami)
WorkingDirectory=/var/www/CHATBOT
Environment="PATH=/var/www/CHATBOT/venv/bin:/usr/bin"
ExecStart=/var/www/CHATBOT/venv/bin/gunicorn --workers 3 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000 app:api --timeout 120
Restart=always

[Install]
WantedBy=multi-user.target
FASTAPI_SERVICE

# Create systemd service for Flask
log_info "Creating Flask service"
sudo tee /etc/systemd/system/chatbot-flask.service > /dev/null << FLASK_SERVICE
[Unit]
Description=CHATBOT Flask API Service
After=network.target

[Service]
User=$(whoami)
Group=$(whoami)
WorkingDirectory=/var/www/CHATBOT
Environment="PATH=/var/www/CHATBOT/venv/bin:/usr/bin"
ExecStart=/var/www/CHATBOT/venv/bin/gunicorn --workers 2 --bind 0.0.0.0:4000 api:app --timeout 120
Restart=always

[Install]
WantedBy=multi-user.target
FLASK_SERVICE

# Start and enable services
log_info "Starting services"
sudo systemctl daemon-reload
sudo systemctl enable chatbot-fastapi.service chatbot-flask.service
sudo systemctl restart chatbot-fastapi.service chatbot-flask.service

# Verify services are running
check_service_status() {
    if systemctl is-active --quiet "$1"; then
        log_info "$1 is running"
    else
        log_error "$1 failed to start"
        exit 1
    fi
}

check_service_status chatbot-fastapi.service
check_service_status chatbot-flask.service

log_info "=== Deployment complete ==="
