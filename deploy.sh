#!/bin/bash
# One-step setup script for EC2 instance
# Run this script directly on your EC2 instance

# Create app directory
mkdir -p ~/chatbot
cd ~/chatbot

# Create .env file for API keys (replace with your actual keys)
cat > .env << 'EOF'
# Google API Keys for Gemini
GOOGLE_API_KEY_1=your_key_1
GOOGLE_API_KEY_2=your_key_2
GOOGLE_API_KEY_3=your_key_3
GOOGLE_API_KEY_4=your_key_4
EOF

# Create comprehensive transcript file with actual content
cat > transcript.txt << 'EOF'
Concrete is a composite material composed of fine and coarse aggregate bonded together with a fluid cement paste that hardens over time. Concrete is the second-most-used substance in the world after water and is the most widely used building material.

In its hardened state, concrete is an aggregation of stones (or similar hard material) embedded in cement-sand mortar. This mortar is formed by combining cement, water, and fine aggregate like sand or stone dust. Larger pieces of aggregate, such as crushed stones, are also included in the mix. Therefore, conventional concrete is made up of cement + water + sand/stone dust + coarse aggregate (stones).

Cement is a binder, a substance used for construction that sets, hardens, and adheres to other materials to bind them together. Cement is seldom used on its own, but rather to bind sand and gravel together. Cement mixed with fine aggregate produces mortar, and cement mixed with sand and gravel produces concrete.

Portland cement is the most common type of cement in general use around the world as a basic ingredient of concrete, mortar, stucco, and non-specialty grout. It was developed from other types of hydraulic lime in England in the early 19th century by Joseph Aspdin, and is usually made from limestone.

The most important properties of concrete are: workability, cohesiveness, strength, and durability. Workability refers to the ease with which concrete can be mixed, transported, placed, compacted, and finished. Cohesiveness refers to the ability of concrete to hold all ingredients together. Strength refers to the ability of concrete to resist stress without failure. Durability refers to the ability of concrete to resist weathering action, chemical attack, and abrasion.

The water-cement ratio is the ratio of the weight of water to the weight of cement used in a concrete mix. A lower ratio leads to higher strength and durability, but may make the mix difficult to work with and form. Workability can be managed by adding chemical admixtures without changing the water-cement ratio.
EOF

# Create the API file
cat > api.py << 'EOF'
from flask import Flask, request, jsonify
import google.generativeai as genai
import os
import re
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Initialize Flask app
app = Flask(__name__)

# Get API keys
def get_api_keys():
    keys = []
    i = 1
    while True:
        key = os.getenv(f"GOOGLE_API_KEY_{i}")
        if key:
            keys.append(key)
            i += 1
        else:
            std_key = os.getenv("GOOGLE_API_KEY")
            if std_key and std_key not in keys:
                keys.append(std_key)
            break
    return keys

API_KEYS = get_api_keys()
CURRENT_KEY_INDEX = 0

# File paths
TRANSCRIPT_FILE = "transcript.txt"

def clean_text(text):
    text = re.sub(r"\s+", " ", text)
    text = text.replace("\n", " ")
    return text.strip()

# Load transcript
try:
    with open(TRANSCRIPT_FILE, "r", encoding="utf-8") as f:
        transcript_text = f.read()
    cleaned_text = clean_text(transcript_text)
    print(f"Successfully loaded transcript with {len(cleaned_text)} characters")
except Exception as e:
    print(f"Warning: Could not read transcript file: {str(e)}")
    cleaned_text = "No transcript available."

# Create chunks without requiring NLTK
def simple_chunk_text(text, chunk_size=500):
    # Split by periods, question marks, and exclamation points
    sentences = re.split(r'[.!?]+', text)
    sentences = [s.strip() for s in sentences if s.strip()]
    
    chunks = []
    current_chunk = ""
    
    for sentence in sentences:
        if len(current_chunk) + len(sentence) < chunk_size:
            current_chunk += " " + sentence
        else:
            chunks.append(current_chunk.strip())
            current_chunk = sentence
    
    if current_chunk:
        chunks.append(current_chunk.strip())
        
    return chunks

# Create chunks
chunks = simple_chunk_text(cleaned_text)
print(f"Created {len(chunks)} chunks from transcript")

# Simple search function (without embeddings)
def search_transcript(query):
    # Simple keyword-based search
    query_terms = query.lower().split()
    scored_chunks = []
    
    for i, chunk in enumerate(chunks):
        score = 0
        chunk_lower = chunk.lower()
        for term in query_terms:
            if term in chunk_lower:
                score += 1
        
        scored_chunks.append((i, score, chunk))
    
    # Sort by score
    scored_chunks.sort(key=lambda x: x[1], reverse=True)
    
    # Return top 3 chunks
    relevant_chunks = [chunk for _, score, chunk in scored_chunks[:3] if score > 0]
    if not relevant_chunks:
        # If no matches, return first few chunks as context
        relevant_chunks = [chunks[i] for i in range(min(3, len(chunks)))]
    
    return " ".join(relevant_chunks)

def generate_response(query):
    global CURRENT_KEY_INDEX
    if not API_KEYS:
        return "Error: No API keys available."
    
    for _ in range(len(API_KEYS)):
        try:
            current_key = API_KEYS[CURRENT_KEY_INDEX]
            genai.configure(api_key=current_key)
            model = genai.GenerativeModel("gemini-1.5-pro-latest")
            
            relevant_text = search_transcript(query)
            
            # Use an improved prompt that encourages more authoritative answers
            prompt = f"""
            You are an expert AI tutor specializing in construction and engineering materials.
            
            IMPORTANT INSTRUCTIONS:
            1. Provide detailed, authoritative answers about construction materials
            2. Use the knowledge below if relevant to the question
            3. NEVER say "the transcript doesn't contain information" - instead, provide your best answer
            4. If asked about concrete, cement, or construction materials, always give a thorough technical explanation
            
            Knowledge from lecture transcript: {relevant_text}
            
            Question: {query}
            """
            
            response = model.generate_content(prompt)
            return response.text
        except Exception as e:
            error_str = str(e).lower()
            if "quota" in error_str or "rate limit" in error_str or "exceeded" in error_str:
                CURRENT_KEY_INDEX = (CURRENT_KEY_INDEX + 1) % len(API_KEYS)
            else:
                return f"Error: {str(e)}"
    return "All API keys have reached their quota limits."

@app.route("/", methods=["GET"])
def home():
    return "Welcome to the Dhamm AI Chatbot API! Use /ask endpoint with a POST request to get answers."

@app.route("/ask", methods=["POST"])
def ask():
    data = request.get_json()  # Get JSON payload from the request
    if not data or "query" not in data:
        return jsonify({"error": "Please provide a query parameter in JSON format."}), 400
    
    query = data["query"]
    response = generate_response(query)
    return jsonify({"answer": response})

@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint"""
    return jsonify({"status": "healthy"}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=4000, debug=False)
EOF

# Set up Python virtual environment
if ! command -v python3 &>/dev/null; then
    echo "Installing Python..."
    sudo apt-get update
    sudo apt-get install -y python3 python3-venv python3-pip
fi

# Create virtual environment
echo "Creating virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Install minimal dependencies
echo "Installing dependencies..."
pip install flask google-generativeai python-dotenv

# Create a systemd service file
echo "Creating systemd service..."
cat > /tmp/chatbot.service << EOF
[Unit]
Description=Chatbot AI Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/chatbot
ExecStart=$HOME/chatbot/venv/bin/python $HOME/chatbot/api.py
Restart=always
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

# Install the service
sudo mv /tmp/chatbot.service /etc/systemd/system/

# Reload systemd, enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable chatbot
sudo systemctl restart chatbot

# Check service status
echo "Service status:"
sudo systemctl status chatbot --no-pager

echo ""
echo "Setup complete! Your chatbot API should now be running."
echo "You can test it with:"
echo "curl -X POST -H \"Content-Type: application/json\" -d '{\"query\":\"What is concrete?\"}' http://localhost:4000/ask"
echo ""
echo "Don't forget to update your API keys in the .env file!"