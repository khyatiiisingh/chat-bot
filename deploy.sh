#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

echo "=== Starting deployment process ==="

# Create destination directory with proper permissions
echo "Setting up app directory"
sudo mkdir -p /var/www/CHATBAOT
sudo chown "$(whoami):$(whoami)" /var/www/CHATBAOT

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
sudo chown -R "$(whoami):$(whoami)" /var/www/CHATBAOT

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

# Verify transcript file exists
if [ ! -f cleaned_transcript.txt ]; then
    echo "WARNING: transcript file not found, creating sample file"
    cat > cleaned_transcript.txt << 'EOF'
Welcome to today's lecture on Artificial Intelligence and Machine Learning.
This is a sample transcript file created during deployment.
AI systems can analyze data, learn patterns, and make decisions.
Machine learning is a subset of AI focused on building systems that learn from data.
Deep learning uses neural networks with multiple layers.
Natural language processing allows computers to understand human language.
Computer vision enables machines to interpret and make decisions based on visual data.
Reinforcement learning involves training agents to make sequences of decisions.
Ethics in AI is important to ensure responsible development and deployment.
Bias in AI systems can lead to unfair outcomes and must be addressed.
The future of AI includes advancements in autonomous systems and general intelligence.
EOF
    echo "Sample transcript file created"
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

# Create a requirements-minimal.txt without problematic packages
cat > requirements-minimal.txt << EOF
streamlit==1.32.0
fastapi==0.109.2
uvicorn==0.27.1
pydantic==2.5.2
# Use compatible versions for langchain and langchain_community
langchain==0.1.0
langchain_community==0.0.14
langchain_google_genai==0.0.6
python-dotenv==1.0.0
gunicorn==21.2.0
EOF

# Install minimal requirements
echo "Installing Python packages in virtual environment"
python3 -m pip install --upgrade pip setuptools wheel
python3 -m pip install uvicorn[standard]
python3 -m pip install -r requirements-minimal.txt

# Create a simple script to verify if we need faiss-cpu
echo "Installing system alternatives for problematic packages"
python3 -c "
import sys
try:
    print('Importing numpy...')
    import numpy
    print('Numpy imported successfully')
    
    # Use system python3-pillow
    print('Setting up PIL path...')
    import site
    site.addsitedir('/usr/lib/python3/dist-packages')
    print('Importing PIL...')
    from PIL import Image
    print('PIL imported successfully:', Image.__version__)
    
    # Try setting up faiss-cpu
    try:
        print('Importing faiss...')
        import faiss
        print('Faiss imported successfully')
    except ImportError:
        print('Faiss not found, using nearest-neighbor alternative')
        # Install scikit-learn as an alternative
        import subprocess
        subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'scikit-learn'])
        print('Installed scikit-learn as alternative')
        
        # Create faiss.py wrapper (simplified version for basic nearest neighbor search)
        with open('faiss.py', 'w') as f:
            f.write('''
# Simplified faiss alternative using scikit-learn
import numpy as np
from sklearn.neighbors import NearestNeighbors

class IndexFlatL2:
    def __init__(self, d):
        self.d = d
        self.nn = None
        self.data = None
    
    def add(self, vectors):
        self.data = vectors
        self.nn = NearestNeighbors(n_neighbors=5, algorithm='auto', metric='l2')
        self.nn.fit(vectors)
    
    def search(self, query, k):
        distances, indices = self.nn.kneighbors(query, n_neighbors=k)
        return distances, indices

def index_factory(d, description):
    return IndexFlatL2(d)
''')
            print('Created faiss alternative')
except Exception as e:
    print('Error in setup:', e)
    sys.exit(1)
"

# Configure and restart Nginx
echo "Configuring Nginx"
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

# Create a systemd service file for the application
echo "Creating systemd service for CHATBAOT"
cat > /tmp/chatbaot.service << EOF
[Unit]
Description=CHATBAOT Gunicorn Service
After=network.target

[Service]
User=$(whoami)
Group=$(whoami)
WorkingDirectory=/var/www/CHATBAOT
Environment="PATH=/var/www/CHATBAOT/venv/bin:/usr/bin"
Environment="PYTHONPATH=/var/www/CHATBAOT:/usr/lib/python3/dist-packages"
ExecStart=/var/www/CHATBAOT/venv/bin/gunicorn --workers 3 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000 app:api --timeout 120
Restart=always

[Install]
WantedBy=multi-user.target
EOF
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