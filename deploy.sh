#!/bin/bash

APP_DIR="/var/www/chatbot"  # Change this to your actual project directory
VENV_DIR="$APP_DIR/venv"    # Virtual environment directory
SERVICE_NAME="chatbot"      # Systemd service name

# Navigate to the application directory
cd $APP_DIR || exit

# Pull the latest changes
git pull origin main

# Activate the virtual environment
source $VENV_DIR/bin/activate

# Install dependencies
pip install --no-cache-dir -r requirements.txt

# Restart the application using systemd
sudo systemctl restart $SERVICE_NAME
