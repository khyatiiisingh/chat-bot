import os
from dotenv import load_dotenv
from langchain.text_splitter import CharacterTextSplitter
from langchain_google_genai import GoogleGenerativeAIEmbeddings, ChatGoogleGenerativeAI
from langchain_community.vectorstores import FAISS
from langchain.memory import ConversationBufferMemory
from langchain.chains import ConversationalRetrievalChain

# Path to the cleaned transcript file
TRANSCRIPT_FILE = "cleaned_transcript.txt"

def load_transcript():
    """Load the cleaned transcript file."""
    if not os.path.exists(TRANSCRIPT_FILE):
        return ""
   
    with open(TRANSCRIPT_FILE, "r", encoding="utf-8") as f:
        return f.read().strip()

def get_text_chunks(text):
    """Split text into smaller chunks for better retrieval."""
    text_splitter = CharacterTextSplitter(
        separator="\n",
        chunk_size=1000,
        chunk_overlap=200,
        length_function=len
    )
    return text_splitter.split_text(text)

def get_vectorstore(text_chunks, api_key):
    """Create FAISS vector database from text chunks."""
    embeddings = GoogleGenerativeAIEmbeddings(
        model="models/text-embedding-004",
        api_key=api_key
    )
    return FAISS.from_texts(texts=text_chunks, embedding=embeddings)

def get_conversation_chain(vectorstore, api_key):
    """Set up the conversational AI chain with memory."""
    llm = ChatGoogleGenerativeAI(
        model='gemini-1.5-pro-latest',
        api_key=api_key
    )
    memory = ConversationBufferMemory(memory_key="chat_history", return_messages=True)
   
    return ConversationalRetrievalChain.from_llm(
        llm=llm,
        retriever=vectorstore.as_retriever(),
        memory=memory
    )

def process_question(conversation_chain, question):
    """Process user queries and generate responses."""
    response = conversation_chain({"question": question})
    return response

def initialize_conversation_chain(api_key):
    """Initialize the conversation chain with the transcript."""
    raw_text = load_transcript()
    if not raw_text:
        return None
   
    text_chunks = get_text_chunks(raw_text)
    vectorstore = get_vectorstore(text_chunks, api_key)
    return get_conversation_chain(vectorstore, api_key)