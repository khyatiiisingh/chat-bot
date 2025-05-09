import os
import sys
import traceback
from dotenv import load_dotenv
import streamlit as st
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import uvicorn

# LangChain + Gemini + FAISS
from langchain.embeddings import GoogleGenerativeAIEmbeddings
from langchain.vectorstores import FAISS
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain.memory import ConversationBufferMemory
from langchain.chains import ConversationalRetrievalChain
from langchain.chat_models import ChatGoogleGenerativeAI
from langchain.docstore.document import Document

# Load environment variables
load_dotenv()
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")

# Globals
conversation_chain = None

# Utility to build vectorstore
def build_vectorstore():
    if not os.path.exists("transcript.txt"):
        raise FileNotFoundError("transcript.txt not found in the project directory.")

    with open("transcript.txt", "r", encoding="utf-8") as f:
        full_text = f.read()

    # Split into chunks
    splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
    documents = splitter.split_documents([Document(page_content=full_text)])

    # Create embeddings
    embeddings = GoogleGenerativeAIEmbeddings(model="models/embedding-001")
    vectorstore = FAISS.from_documents(documents, embedding=embeddings)
    return vectorstore

# Initialize conversation chain
def initialize_conversation_chain():
    vectorstore = build_vectorstore()
    retriever = vectorstore.as_retriever()
    memory = ConversationBufferMemory(memory_key="chat_history", return_messages=True)

    chain = ConversationalRetrievalChain.from_llm(
        llm=ChatGoogleGenerativeAI(model="gemini-pro", temperature=0),
        retriever=retriever,
        memory=memory,
        return_source_documents=True
    )
    return chain

# Process user question
def process_question(chain, question):
    response = chain.invoke({"question": question})
    return {
        "answer": response["answer"],
        "chat_history": chain.memory.chat_memory.messages
    }

# ---------- Streamlit UI ----------
def main():
    st.set_page_config(page_title="Lecture Chatbot", page_icon=":books:")

    if "conversation" not in st.session_state:
        st.session_state.conversation = None
    if "chat_history" not in st.session_state:
        st.session_state.chat_history = []

    st.header("Lecture Chatbot :books:")

    if not GOOGLE_API_KEY:
        st.error("Google API Key is missing! Set it in .env")
        st.stop()

    if st.session_state.conversation is None:
        with st.spinner("Loading transcript and building vector index..."):
            try:
                st.session_state.conversation = initialize_conversation_chain()
                st.success("Transcript loaded and vector index created!")
            except Exception as e:
                st.error(f"Error: {str(e)}")
                st.stop()

    user_question = st.text_input("Ask a question about the lecture:")
    if user_question and st.session_state.conversation:
        with st.spinner("Thinking..."):
            try:
                response = process_question(st.session_state.conversation, user_question)
                st.session_state.chat_history = response["chat_history"]

                st.write(f"**Question:** {user_question}")
                st.write(f"**Answer:** {response['answer']}")

                if st.checkbox("Show chat history"):
                    for i, msg in enumerate(st.session_state.chat_history):
                        speaker = "User" if i % 2 == 0 else "Bot"
                        st.markdown(f"**{speaker}:** {msg.content}")
            except Exception as e:
                st.error(f"Error: {str(e)}")

# ---------- FastAPI API ----------
api = FastAPI(title="Lecture Chatbot API")

class QuestionRequest(BaseModel):
    question: str

@api.on_event("startup")
async def startup_event():
    global conversation_chain
    try:
        if not GOOGLE_API_KEY:
            raise Exception("Google API Key is missing")
        conversation_chain = initialize_conversation_chain()
    except Exception as e:
        print("Startup error:", e)
        print(traceback.format_exc())
        raise

@api.exception_handler(Exception)
async def universal_exception_handler(request: Request, exc: Exception):
    return JSONResponse(status_code=500, content={"detail": str(exc)})

@api.post("/api/ask")
async def ask(request: QuestionRequest):
    global conversation_chain
    if not conversation_chain:
        raise HTTPException(status_code=500, detail="Conversation chain not initialized")
    try:
        response = process_question(conversation_chain, request.question)
        return {"answer": response["answer"]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@api.get("/")
def root():
    return {"message": "API is running. Use /api/ask endpoint to ask questions."}

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == "api":
        uvicorn.run("app:api", host="0.0.0.0", port=8000, reload=True)
    else:
        main()
