name: Deploy CHATBAOT to EC2 🚀

on:
  push:
    branches:
      - "main" # Trigger on push to the main branch
  workflow_dispatch: # Allow manual triggering

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout current branch ✅
        uses: actions/checkout@v3

      - name: Debug - List files in repository
        run: ls -la

      - name: Set up SSH key and whitelist EC2 IP address 🐻‍❄️
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.EC2_SSH_KEY }}" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
          ssh-keyscan -H ${{ secrets.EC2_HOST }} >> ~/.ssh/known_hosts
          ssh -o StrictHostKeyChecking=no ${{ secrets.EC2_USERNAME }}@${{ secrets.EC2_HOST }} "echo SSH connection successful"

      - name: Create .env file dynamically 🧨
        run: |
          echo "ENV=${{ secrets.ENV }}" > env
          echo "EC2_USERNAME=${{ secrets.EC2_USERNAME }}" >> env
          echo "GOOGLE_API_KEY=${{ secrets.GOOGLE_API_KEY }}" >> env

      - name: Create sample transcript files if they don't exist
        run: |
          if [ ! -f cleaned_transcript.txt ]; then
            echo "Creating cleaned transcript file..."
            echo "Welcome to today's lecture on Artificial Intelligence and Machine Learning." > cleaned_transcript.txt
            echo "This is a sample transcript file created during deployment." >> cleaned_transcript.txt
            echo "AI systems can analyze data, learn patterns, and make decisions." >> cleaned_transcript.txt
            echo "Machine learning is a subset of AI focused on building systems that learn from data." >> cleaned_transcript.txt
            echo "Deep learning uses neural networks with multiple layers." >> cleaned_transcript.txt
            echo "Natural language processing allows computers to understand human language." >> cleaned_transcript.txt
            echo "Computer vision enables machines to interpret and make decisions based on visual data." >> cleaned_transcript.txt
            echo "Reinforcement learning involves training agents to make sequences of decisions." >> cleaned_transcript.txt
            echo "Ethics in AI is important to ensure responsible development and deployment." >> cleaned_transcript.txt
            echo "Bias in AI systems can lead to unfair outcomes and must be addressed." >> cleaned_transcript.txt
            echo "The future of AI includes advancements in autonomous systems and general intelligence." >> cleaned_transcript.txt
          fi

          if [ ! -f combined_transcript.txt ]; then
            echo "Creating combined transcript file..."
            echo "Welcome to today's lecture on Artificial Intelligence and Machine Learning." > combined_transcript.txt
            echo "This is a sample combined transcript file created during deployment." >> combined_transcript.txt
            echo "AI systems can analyze data, learn patterns, and make decisions." >> combined_transcript.txt
            echo "Machine learning is a subset of AI focused on building systems that learn from data." >> combined_transcript.txt
            echo "Deep learning uses neural networks with multiple layers." >> combined_transcript.txt
            echo "Natural language processing allows computers to understand human language." >> combined_transcript.txt
            echo "Computer vision enables machines to interpret and make decisions based on visual data." >> combined_transcript.txt
            echo "Reinforcement learning involves training agents to make sequences of decisions." >> combined_transcript.txt
          fi

      - name: Create requirements.txt if not exists
        run: |
          if [ ! -f requirements.txt ]; then
            echo "streamlit==1.32.0" > requirements.txt
            echo "fastapi==0.109.2" >> requirements.txt
            echo "uvicorn==0.27.1" >> requirements.txt
            echo "pydantic==2.5.2" >> requirements.txt
            echo "langchain==0.1.0" >> requirements.txt
            echo "langchain_community==0.0.14" >> requirements.txt
            echo "langchain_google_genai==0.0.6" >> requirements.txt
            echo "python-dotenv==1.0.0" >> requirements.txt
            echo "gunicorn==21.2.0" >> requirements.txt
            echo "faiss-cpu==1.7.4" >> requirements.txt
          fi

      - name: Copy deploy.sh to repository
        run: |
          cat > deploy.sh << 'EOF'
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

# Verify transcript files exist
if [ ! -f cleaned_transcript.txt ]; then
    echo "WARNING: cleaned_transcript.txt not found, creating sample file"
    echo "Welcome to today's lecture on Artificial Intelligence and Machine Learning." > cleaned_transcript.txt
    echo "This is a sample transcript file created during deployment." >> cleaned_transcript.txt
    echo "AI systems can analyze data, learn patterns, and make decisions." >> cleaned_transcript.txt
    echo "Machine learning is a subset of AI focused on building systems that learn from data." >> cleaned_transcript.txt
    echo "Deep learning uses neural networks with multiple layers." >> cleaned_transcript.txt
    echo "Natural language processing allows computers to understand human language." >> cleaned_transcript.txt
    echo "Sample transcript file created"
fi

if [ ! -f combined_transcript.txt ]; then
    echo "WARNING: combined_transcript.txt not found, creating sample file"
    echo "Welcome to today's lecture on Artificial Intelligence and Machine Learning." > combined_transcript.txt
    echo "This is a sample combined transcript file created during deployment." >> combined_transcript.txt
    echo "AI systems can analyze data, learn patterns, and make decisions." >> combined_transcript.txt
    echo "Sample combined transcript file created"
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
python3 -m pip install uvicorn[standard]
python3 -m pip install fastapi==0.109.2 streamlit==1.32.0 pydantic==2.5.2
python3 -m pip install langchain==0.1.0 langchain_community==0.0.14 langchain_google_genai==0.0.6
python3 -m pip install python-dotenv==1.0.0 gunicorn==21.2.0 scikit-learn
python3 -m pip install faiss-cpu==1.7.4

# Fix transcription.py to handle Gemini SystemMessages issue
if grep -q "ChatGoogleGenerativeAI" transcription.py; then
    echo "Updating transcription.py to fix Gemini SystemMessages issue"
    sed -i 's/model='\''gemini-1.5-pro-latest'\'', api_key=api_key/model='\''gemini-1.5-pro-latest'\'', api_key=api_key, convert_system_message_to_human=True/g' transcription.py
    echo "transcription.py updated"
fi

# Configure and restart Nginx
echo "Configuring Nginx"
sudo tee /etc/nginx/sites-available/chatbaot > /dev/null << NGINX_EOF
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

sudo ln -sf /etc/nginx/sites-available/chatbaot /etc/nginx/sites-enabled
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

# Create a systemd service file for the application
echo "Creating systemd service for CHATBAOT"
sudo tee /etc/systemd/system/chatbaot.service > /dev/null << SERVICE_EOF
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
SERVICE_EOF

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
EOF
          chmod +x deploy.sh

      - name: Copy files to remote server 🚙
        run: |
          echo "Copying files to remote server"
          scp -r app.py transcription.py requirements.txt env deploy.sh cleaned_transcript.txt combined_transcript.txt ${{ secrets.EC2_USERNAME }}@${{ secrets.EC2_HOST }}:~/

      - name: Run Bash Script To Deploy App 🚀
        run: |
          ssh -o StrictHostKeyChecking=no ${{ secrets.EC2_USERNAME }}@${{ secrets.EC2_HOST }} "chmod +x ./deploy.sh && ./deploy.sh"

      - name: Clean up SSH key 🚀
        if: always()
        run: |
          rm -f ~/.ssh/id_rsa