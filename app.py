import streamlit as st
import os
from dotenv import load_dotenv
from transcription import initialize_conversation_chain, process_question
import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import sys
import traceback

# Load environment variables
load_dotenv()

# Retrieve Google API Key from environment variable
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")

# Main Streamlit app
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
            try:
                st.session_state.conversation = initialize_conversation_chain(GOOGLE_API_KEY)
                if st.session_state.conversation:
                    st.success("Transcript loaded successfully!")
                else:
                    st.error("Transcript file 'cleaned_transcript.txt' not found!")
                    st.stop()
            except Exception as e:
                st.error(f"Error initializing conversation: {str(e)}")
                st.stop()
    
    # User input for questions
    user_question = st.text_input("Ask a question about the lecture:")
    if user_question and st.session_state.conversation:
        # Process the question
        with st.spinner("Processing your question..."):
            try:
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
            except Exception as e:
                st.error(f"Error processing question: {str(e)}")

# Create FastAPI app
api = FastAPI(title="Lecture Chatbot API")

# Define request model
class QuestionRequest(BaseModel):
    question: str

# Global conversation chain
conversation_chain = None

# Error handler
@api.exception_handler(Exception)
async def universal_exception_handler(request: Request, exc: Exception):
    return JSONResponse(
        status_code=500,
        content={"detail": str(exc)},
    )

@api.on_event("startup")
async def startup_event():
    global conversation_chain
    try:
        # Load environment variables
        load_dotenv()
        # Get API key
        api_key = os.getenv("GOOGLE_API_KEY")
        if not api_key:
            print("Error: Google API Key is missing")
            raise Exception("Google API Key is missing")
            
        # Initialize conversation chain
        print("Initializing conversation chain...")
        conversation_chain = initialize_conversation_chain(api_key)
        
        if not conversation_chain:
            print("Error: Failed to initialize conversation chain")
            raise Exception("Failed to initialize conversation chain")
            
        print("Conversation chain initialized successfully")
    except Exception as e:
        print(f"Startup error: {str(e)}")
        print(traceback.format_exc())
        raise Exception(f"Startup error: {str(e)}")

@api.post("/api/ask")
async def ask(request: QuestionRequest):
    global conversation_chain
    if not conversation_chain:
        raise HTTPException(status_code=500, detail="Conversation chain not initialized")
    
    try:
        print(f"Processing question: {request.question}")
        response = process_question(conversation_chain, request.question)
        print(f"Got response: {response['answer']}")
        return {"answer": response["answer"]}
    except Exception as e:
        print(f"Error processing question: {str(e)}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Error: {str(e)}")

# Root endpoint
@api.get("/")
def read_root():
    return {"message": "API is running. Use /api/ask endpoint to ask questions."}

if __name__ == '__main__':
    # Check if running as a script or imported as a module
    if len(sys.argv) > 1 and sys.argv[1] == "api":
        # Run FastAPI with uvicorn
        uvicorn.run("app:api", host="0.0.0.0", port=8000, reload=True)
    else:
        # Run Streamlit app
        main()