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

# Restore .env file
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

# Create and configure Nginx
log_info "Configuring Nginx"
cat > /tmp/nginx_conf << EOF
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
EOF

sudo mv /tmp/nginx_conf /etc/nginx/sites-available/chatbot
sudo ln -sf /etc/nginx/sites-available/chatbot /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx

# Restart services
log_info "Starting services"
sudo systemctl daemon-reload
sudo systemctl restart chatbot-fastapi.service chatbot-flask.service

log_info "=== Deployment complete ==="
