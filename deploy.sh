#!/bin/bash
set -e  # Exit immediately if a command fails

# Configuration variables
APP_DIR=${APP_DIR:-"/var/www/chatbot"}
VENV_DIR=${VENV_DIR:-"$APP_DIR/venv"}
SERVICE_NAME=${SERVICE_NAME:-"chatbot"}

# Make sure the script is being run with the right permissions
if [ "$EUID" -ne 0 ] && [ ! -w "/etc/systemd/system" ]; then
    echo "Please run as root or with sudo privileges"
    exit 1
fi

echo "Starting deployment..."

# Create working directory if it doesn't exist
mkdir -p $APP_DIR

# Set working directory
cd $APP_DIR

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment..."
    python3 -m venv $VENV_DIR
fi

# Activate virtual environment
echo "Activating virtual environment..."
source $VENV_DIR/bin/activate

# Install dependencies
echo "Installing dependencies..."
pip install --upgrade pip
if [ -f requirements.txt ]; then
    pip install --no-cache-dir -r requirements.txt
fi

# Make sure nltk data is downloaded
python -c "import nltk; nltk.download('punkt'); nltk.download('punkt_tab')"

# Create empty transcript file if it doesn't exist
if [ ! -f "transcript.txt" ]; then
    echo "Creating empty transcript.txt file..."
    echo "Sample transcript content for testing deployment." > transcript.txt
fi

# Create systemd service file
echo "Creating systemd service file..."
cat > /tmp/$SERVICE_NAME.service << EOF
[Unit]
Description=Chatbot AI Service
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

# Move service file to systemd
sudo mv /tmp/$SERVICE_NAME.service /etc/systemd/system/

# Reload systemd daemon
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

# Enable service
echo "Enabling service..."
sudo systemctl enable $SERVICE_NAME

# Restart the application using systemd
echo "Restarting the application service..."
sudo systemctl restart $SERVICE_NAME

# Check the status of the service
echo "Checking service status..."
sudo systemctl status $SERVICE_NAME --no-pager

echo "Deployment completed successfully!"