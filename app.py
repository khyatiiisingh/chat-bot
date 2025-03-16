import streamlit as st
import os
from dotenv import load_dotenv
from transcription import initialize_conversation_chain, process_question

# Load environment variables
load_dotenv()

# Retrieve Google API Key from environment variable
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")

def main():
    st.set_page_config(page_title="Lecture Chatbot", page_icon=":books:")
    
    if "conversation" not in st.session_state:
        st.session_state.conversation = None
    if "chat_history" not in st.session_state:
        st.session_state.chat_history = []
    
    st.header("Lecture Chatbot :books:")
    
    # Check if API key is available
    if not GOOGLE_API_KEY:
        st.error("Google API Key is missing! Set it as an environment variable.")
        st.stop()
    
    # Initialize conversation (only once)
    if st.session_state.conversation is None:
        with st.spinner("Loading transcript..."):
            st.session_state.conversation = initialize_conversation_chain(GOOGLE_API_KEY)
            if st.session_state.conversation:
                st.success("Transcript loaded successfully!")
            else:
                st.error("Transcript file 'cleaned_transcript.txt' not found!")
                st.stop()
    
    # User input for questions
    user_question = st.text_input("Ask a question about the lecture:")
    if user_question and st.session_state.conversation:
        # Process the question
        response = process_question(st.session_state.conversation, user_question)
        
        # Update chat history
        st.session_state.chat_history = response['chat_history']
        
        # Display the response
        st.write(f"**Question:** {user_question}")
        st.write(f"**Answer:** {response['answer']}")
        
        # Display chat history (optional)
        if st.checkbox("Show chat history"):
            for i, message in enumerate(st.session_state.chat_history):
                if i % 2 == 0:
                    st.write(f"**User:** {message.content}")
                else:
                    st.write(f"**Bot:** {message.content}")
                st.write("---")

# Add REST API endpoint using FastAPI
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.wsgi import WSGIMiddleware
from pydantic import BaseModel
import uvicorn

# Create FastAPI app
api = FastAPI(title="Lecture Chatbot API")

# Define request model
class QuestionRequest(BaseModel):
    question: str

# Global conversation chain
conversation_chain = None

@api.on_event("startup")
async def startup_event():
    global conversation_chain
    # Load environment variables
    load_dotenv()
    # Get API key
    api_key = os.getenv("GOOGLE_API_KEY")
    if not api_key:
        raise HTTPException(status_code=500, detail="Google API Key is missing")
    # Initialize conversation chain
    conversation_chain = initialize_conversation_chain(api_key)
    if not conversation_chain:
        raise HTTPException(status_code=500, detail="Failed to initialize conversation chain")

@api.post("/api/ask")
async def ask(request: QuestionRequest):
    global conversation_chain
    if not conversation_chain:
        raise HTTPException(status_code=500, detail="Conversation chain not initialized")
    
    try:
        response = process_question(conversation_chain, request.question)
        return {"answer": response["answer"]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error processing question: {str(e)}")

# Mount Streamlit app (fixed from original code)
@api.get("/")
def read_root():
    return {"message": "API is running. Use /api/ask endpoint to ask questions."}

if __name__ == '__main__':
    # Check if running as a script or imported as a module
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "api":
        # Run FastAPI with uvicorn
        uvicorn.run("app:api", host="0.0.0.0", port=8000, reload=True)
    else:
        # Run Streamlit app
        main()