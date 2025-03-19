#!/bin/bash
set -e  # Exit immediately if a command fails

# Configuration variables
APP_DIR="/var/www/chatbot"    # Update this with your actual project directory
VENV_DIR="$APP_DIR/venv"      # Virtual environment directory
SERVICE_NAME="chatbot"        # Systemd service name
GIT_BRANCH="main"             # Git branch to deploy
REPO_URL="https://github.com/Venktesh123/chat-boat.git" # Update with your actual repo URL

echo "Starting deployment process..."

# Create app directory if it doesn't exist
if [ ! -d "$APP_DIR" ]; then
    echo "Creating application directory..."
    mkdir -p $APP_DIR
    cd $APP_DIR
    git clone $REPO_URL .
else
    # Navigate to the application directory
    cd $APP_DIR || exit 1
    echo "Pulling latest changes from Git..."
    git fetch --all
    git reset --hard origin/$GIT_BRANCH
fi

# Ensure virtual environment exists
if [ ! -d "$VENV_DIR" ]; then
    echo "Virtual environment not found! Creating one..."
    python3 -m venv $VENV_DIR
fi

# Activate the virtual environment
echo "Activating virtual environment..."
source $VENV_DIR/bin/activate

# Install dependencies
echo "Installing dependencies..."
pip install --upgrade pip
pip install --no-cache-dir -r requirements.txt

# Set environment variables from GitHub secrets
echo "Setting up environment variables..."
# You may need to create a .env file or configure these in your systemd service
# These are the secrets visible in your GitHub repository
if [ -f .env ]; then
    echo "Updating .env file..."
else
    echo "Creating .env file..."
    touch .env
fi

# Create or update systemd service if it doesn't exist
if [ ! -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
    echo "Creating systemd service..."
    cat > /tmp/$SERVICE_NAME.service << EOF
[Unit]
Description=Chatbot Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$APP_DIR
ExecStart=$VENV_DIR/bin/python $APP_DIR/api.py
Restart=always
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /tmp/$SERVICE_NAME.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
fi

# Restart the application using systemd
echo "Restarting the application service..."
sudo systemctl restart $SERVICE_NAME

# Check the status of the service
echo "Checking service status..."
sudo systemctl status $SERVICE_NAME --no-pager

echo "Deployment completed successfully!"