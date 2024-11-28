from contextlib import asynccontextmanager
import time
import json
import os
from fastapi import FastAPI, HTTPException, UploadFile, File
from langchain_chroma import Chroma
from langchain.prompts import ChatPromptTemplate
from langchain_ollama import OllamaLLM
from pydantic import BaseModel
from langchain_ollama import OllamaEmbeddings
from typing import List
from fastapi.responses import FileResponse


with open("config.json", "r") as config_file:
    config = json.load(config_file)


CHROMA_PATH = os.getenv("CHROMA_PATH", config["chroma_path"])
DATA_PATH = os.getenv("DATA_PATH", config["data_path"])
LOG_FILE = os.getenv("LOG_FILE", config["log_file"])
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", config["ollama_base_url"])
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", config["models"]["embedding_model"])
LLAMA_MODEL = os.getenv("LLAMA_MODEL", config["models"]["llama_model"])

PROMPT_TEMPLATE = """
Answer the question based only on the following context:

{context}

---

Answer the question based on the above context: {question}
"""


db = None
model = None
first_request = True
change_made = ""


class QueryRequest(BaseModel):
    query_text: str


@asynccontextmanager
async def lifespan(app: FastAPI):
    global db, model
    
    start_time = time.time()
    print("🚀 Initializing Chroma...")
    db = Chroma(
        persist_directory=CHROMA_PATH,
        embedding_function=OllamaEmbeddings(model=EMBEDDING_MODEL, base_url=OLLAMA_BASE_URL),
    )
    print(f"✅ Chroma initialized in {time.time() - start_time:.2f} seconds.")

    start_time = time.time()
    print("🚀 Initializing Ollama model...")
    model = OllamaLLM(model=f"{LLAMA_MODEL}:3b", base_url=OLLAMA_BASE_URL)
    print(f"✅ Ollama model initialized in {time.time() - start_time:.2f} seconds.")

    yield  


app = FastAPI(lifespan=lifespan)


def log_to_json(data: dict):
    try:
        logs = []
        try:
            with open(LOG_FILE, "r") as f:
                logs = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            pass
        logs.append(data)
        with open(LOG_FILE, "w") as f:
            json.dump(logs, f, indent=4)
    except Exception as e:
        print(f"Error logging data: {e}")


def create_log_entry(
    query_text: str,
    response: str = None,
    sources: list = None,
    processing_time: float = None,
    search_time: float = None,
    model_time: float = None,
    error: str = None,
):
    global first_request, change_made
    return {
        "query_text": query_text,
        "response": response,
        "sources": sources,
        "total_time_seconds": round(processing_time, 3) if processing_time else None,
        "search_time_seconds": round(search_time, 3) if search_time else None,
        "model_time_seconds": round(model_time, 3) if model_time else None,
        "first_request": first_request,
        "change_made": change_made,
        "error": error or "None",
    }

@app.get("/")
def root():
    """Root endpoint to verify the API is running."""
    return {"message": "Welcome to the RAG API. Use the /query endpoint to interact with the LLM"}

@app.post("/query/")
def query_rag(request: QueryRequest):
    """Query endpoint for the LLM."""
    global first_request, db, model
    start_time = time.time()

    try:
        
        search_start = time.time()
        results = db.similarity_search_with_score(request.query_text, k=5)
        search_time = time.time() - search_start

        
        context_text = "\n\n---\n\n".join([doc.page_content for doc, _ in results])
        prompt_template = ChatPromptTemplate.from_template(PROMPT_TEMPLATE)
        prompt = prompt_template.format(context=context_text, question=request.query_text)

        model_start = time.time()
        response_text = model.invoke(prompt)
        model_time = time.time() - model_start

        
        sources = [doc.metadata.get("id", None) for doc, _ in results]
        processing_time = time.time() - start_time

        
        log_entry = create_log_entry(
            query_text=request.query_text,
            response=response_text,
            sources=sources,
            processing_time=processing_time,
            search_time=search_time,
            model_time=model_time,
        )
        log_to_json(log_entry)
        first_request = False
        return log_entry

    except Exception as e:
        processing_time = time.time() - start_time
        error_entry = create_log_entry(
            query_text=request.query_text,
            processing_time=processing_time,
            error=str(e),
        )
        log_to_json(error_entry)
        first_request = False
        raise HTTPException(status_code=500, detail=error_entry)

@app.get("/files/")
def list_files():
    """List all files in the data directory."""
    try:
        files = os.listdir(DATA_PATH)
        file_info = [{"name": f, "size": os.path.getsize(os.path.join(DATA_PATH, f))} for f in files]
        return {"files": file_info}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/files/{filename}")
def delete_file(filename: str):
    """Delete a file from the data directory."""
    file_path = os.path.join(DATA_PATH, filename)
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="File not found.")
    try:
        os.remove(file_path)
        return {"message": f"File '{filename}' deleted successfully."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.put("/files/{filename}")
def rename_file(filename: str, new_name: str):
    """Rename a file in the data directory."""
    old_path = os.path.join(DATA_PATH, filename)
    new_path = os.path.join(DATA_PATH, new_name)
    if not os.path.exists(old_path):
        raise HTTPException(status_code=404, detail="File not found.")
    try:
        os.rename(old_path, new_path)
        return {"message": f"File '{filename}' renamed to '{new_name}' successfully."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/files/")
def add_file(file: UploadFile = File(...)):
    """Upload a file to the data directory."""
    file_path = os.path.join(DATA_PATH, file.filename)
    try:
        with open(file_path, "wb") as f:
            f.write(file.file.read())
        return {"message": f"File '{file.filename}' uploaded successfully."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/files/download/{filename}")
def download_file(filename: str):
    """Download a file from the data directory."""
    file_path = os.path.join(DATA_PATH, filename)
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="File not found.")
    try:
        return FileResponse(file_path, media_type="application/octet-stream", filename=filename)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
