from flask import Flask, request, jsonify
import google.generativeai as genai
import os
import re
from dotenv import load_dotenv
from flask_cors import CORS

# Load environment variables
load_dotenv()

# Initialize Flask app
app = Flask(__name__)

# Enable CORS with specific settings
CORS(app, resources={r"/*": {
    "origins": "https://kiit-lms.vercel.app",
    "methods": ["GET", "POST", "OPTIONS"],
    "allow_headers": ["Content-Type", "Authorization"]
}})

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

def get_next_api_key():
    global CURRENT_KEY_INDEX
    if not API_KEYS:
        return None
    CURRENT_KEY_INDEX = (CURRENT_KEY_INDEX + 1) % len(API_KEYS)
    return API_KEYS[CURRENT_KEY_INDEX]

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
    
    # If no relevant chunks found, return empty string instead of filler content
    if not relevant_chunks:
        return ""
    
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
            
            # Check if search found anything useful
            if not relevant_text or len(relevant_text.strip()) < 50:
                # Instead of using general knowledge, return a "not found" message
                return "This lecture transcript does not contain information about Benjamin Franklin. Therefore, I am unable to answer your question."
            else:
                # Use transcript-based prompt if relevant content found
                prompt = f"""
                You are a helpful AI assistant that answers questions based ONLY on the given lecture transcript content.
                
                Lecture Context: {relevant_text}
                
                Question: {query}
                
                Important guidelines:
                1. Only answer using information from the provided lecture context.
                2. If the lecture context doesn't contain information to answer the question, simply state:
                   "This lecture transcript does not contain information about Benjamin Franklin. Therefore, I am unable to answer your question."
                3. Do not use any external knowledge.
                4. Keep your answer concise and to the point.
                5. Don't use markdown formatting, asterisks, or other special characters.
                6. Format your response as plain text only.
                """
            
            response = model.generate_content(prompt)
            return response.text.strip()
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

# Add OPTIONS method handler for preflight requests
@app.route("/ask", methods=["OPTIONS"])
def options_ask():
    return "", 200

@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint"""
    return jsonify({"status": "healthy"}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=4000, debug=False)




# from flask import Flask, request, jsonify
# import google.generativeai as genai
# import os
# import re
# from dotenv import load_dotenv
# from flask_cors import CORS

# # Load environment variables
# load_dotenv()

# # Initialize Flask app
# app = Flask(__name__)

# # Enable CORS with specific settings
# CORS(app, resources={r"/*": {
#     "origins": "https://kiit-lms.vercel.app",
#     "methods": ["GET", "POST", "OPTIONS"],
#     "allow_headers": ["Content-Type", "Authorization"]
# }})

# # Get API keys
# def get_api_keys():
#     keys = []
#     i = 1
#     while True:
#         key = os.getenv(f"GOOGLE_API_KEY_{i}")
#         if key:
#             keys.append(key)
#             i += 1
#         else:
#             std_key = os.getenv("GOOGLE_API_KEY")
#             if std_key and std_key not in keys:
#                 keys.append(std_key)
#             break
#     return keys

# API_KEYS = get_api_keys()
# CURRENT_KEY_INDEX = 0

# def get_next_api_key():
#     global CURRENT_KEY_INDEX
#     if not API_KEYS:
#         return None
#     CURRENT_KEY_INDEX = (CURRENT_KEY_INDEX + 1) % len(API_KEYS)
#     return API_KEYS[CURRENT_KEY_INDEX]

# # File paths
# TRANSCRIPT_FILE = "transcript.txt"

# def clean_text(text):
#     text = re.sub(r"\s+", " ", text)
#     text = text.replace("\n", " ")
#     return text.strip()

# # Load transcript
# try:
#     with open(TRANSCRIPT_FILE, "r", encoding="utf-8") as f:
#         transcript_text = f.read()
#     cleaned_text = clean_text(transcript_text)
# except Exception as e:
#     print(f"Warning: Could not read transcript file: {str(e)}")
#     cleaned_text = "No transcript available."

# # Create chunks without requiring NLTK
# def simple_chunk_text(text, chunk_size=500):
#     # Split by periods, question marks, and exclamation points
#     sentences = re.split(r'[.!?]+', text)
#     sentences = [s.strip() for s in sentences if s.strip()]
    
#     chunks = []
#     current_chunk = ""
    
#     for sentence in sentences:
#         if len(current_chunk) + len(sentence) < chunk_size:
#             current_chunk += " " + sentence
#         else:
#             chunks.append(current_chunk.strip())
#             current_chunk = sentence
    
#     if current_chunk:
#         chunks.append(current_chunk.strip())
        
#     return chunks

# # Create chunks
# chunks = simple_chunk_text(cleaned_text)

# # Simple search function (without embeddings)
# def search_transcript(query):
#     # Simple keyword-based search
#     query_terms = query.lower().split()
#     scored_chunks = []
    
#     for i, chunk in enumerate(chunks):
#         score = 0
#         chunk_lower = chunk.lower()
#         for term in query_terms:
#             if term in chunk_lower:
#                 score += 1
        
#         scored_chunks.append((i, score, chunk))
    
#     # Sort by score
#     scored_chunks.sort(key=lambda x: x[1], reverse=True)
    
#     # Return top 3 chunks
#     relevant_chunks = [chunk for _, score, chunk in scored_chunks[:3] if score > 0]
    
#     # If no relevant chunks found, return empty string instead of filler content
#     if not relevant_chunks:
#         return ""
    
#     return " ".join(relevant_chunks)

# def generate_response(query):
#     global CURRENT_KEY_INDEX
#     if not API_KEYS:
#         return "Error: No API keys available."
    
#     for _ in range(len(API_KEYS)):
#         try:
#             current_key = API_KEYS[CURRENT_KEY_INDEX]
#             genai.configure(api_key=current_key)
#             model = genai.GenerativeModel("gemini-1.5-pro-latest")
            
#             relevant_text = search_transcript(query)
            
#             # Check if search found anything useful
#             if not relevant_text or len(relevant_text.strip()) < 50:
#                 # Use general knowledge prompt if no relevant content found
#                 prompt = f"""
#                 You are an expert AI tutor specializing in construction, engineering, materials science, and related fields.
#                 Answer the following question thoroughly and authoritatively based on your knowledge:
                
#                 Question: {query}
                
#                 Important: Provide a complete, accurate, and educational answer. Do not mention that you don't have specific information.
#                 If this is about concrete, cement, construction materials, or related topics, provide detailed technical information.
#                 """
#             else:
#                 # Use transcript-based prompt if relevant content found
#                 prompt = f"""
#                 You are an expert AI tutor. Answer the following question based on the given information:
                
#                 Lecture Context: {relevant_text}
                
#                 Question: {query}
                
#                 Important: If the lecture context doesn't fully address the question, supplement with your knowledge to provide a complete answer.
#                 Never say "the provided text doesn't contain information" - instead, provide the best answer you can.
#                 """
            
#             response = model.generate_content(prompt)
#             return response.text
#         except Exception as e:
#             error_str = str(e).lower()
#             if "quota" in error_str or "rate limit" in error_str or "exceeded" in error_str:
#                 CURRENT_KEY_INDEX = (CURRENT_KEY_INDEX + 1) % len(API_KEYS)
#             else:
#                 return f"Error: {str(e)}"
#     return "All API keys have reached their quota limits."

# @app.route("/", methods=["GET"])
# def home():
#     return "Welcome to the Dhamm AI Chatbot API! Use /ask endpoint with a POST request to get answers."

# @app.route("/ask", methods=["POST"])
# def ask():
#     data = request.get_json()  # Get JSON payload from the request
#     if not data or "query" not in data:
#         return jsonify({"error": "Please provide a query parameter in JSON format."}), 400
    
#     query = data["query"]
#     response = generate_response(query)
#     return jsonify({"answer": response})

# # Add OPTIONS method handler for preflight requests
# @app.route("/ask", methods=["OPTIONS"])
# def options_ask():
#     return "", 200

# @app.route("/health", methods=["GET"])
# def health_check():
#     """Health check endpoint"""
#     return jsonify({"status": "healthy"}), 200

# if __name__ == "__main__":
#     app.run(host="0.0.0.0", port=4000, debug=False)