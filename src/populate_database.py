import os
import json
import argparse
import time
from typing import List
from langchain_chroma import Chroma
from langchain_ollama import OllamaEmbeddings
from langchain_community.document_loaders import PyPDFDirectoryLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain.schema.document import Document


with open("config.json", "r") as config_file:
    config = json.load(config_file)


OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", config["ollama_base_url"])
DATA_PATH = os.getenv("DATA_PATH", config["data_path"])
CHROMA_PATH = os.getenv("CHROMA_PATH", config["chroma_path"])
EMBEDDING_MODEL = "mxbai-embed-large"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--reset", action="store_true", help="Reset the database.")
    args = parser.parse_args()

    if args.reset:
        print("✨ Clearing Database...")
        clear_database()

    print("🚀 Synchronizing with directory...")
    sync_start_time = time.time()
    sync_with_directory()
    print(f"✅ Directory synchronization completed in {time.time() - sync_start_time:.2f} seconds.")

    print("📂 Loading documents...")
    load_start_time = time.time()
    documents = load_documents()
    print(f"✅ Loaded {len(documents)} documents in {time.time() - load_start_time:.2f} seconds.")

    print("🔗 Splitting documents into chunks...")
    split_start_time = time.time()
    chunks = split_documents(documents)
    print(f"✅ Split into {len(chunks)} chunks in {time.time() - split_start_time:.2f} seconds.")

    print("📥 Adding chunks to Chroma database...")
    add_start_time = time.time()
    add_to_chroma(chunks)
    print(f"✅ Added chunks to Chroma in {time.time() - add_start_time:.2f} seconds.")


def load_documents() -> List[Document]:
    """Load all PDF documents from the data directory."""
    document_loader = PyPDFDirectoryLoader(DATA_PATH)
    return document_loader.load()


def split_documents(documents: List[Document]) -> List[Document]:
    """Split documents into smaller chunks for processing."""
    text_splitter = RecursiveCharacterTextSplitter(chunk_size=800, chunk_overlap=80)
    return text_splitter.split_documents(documents)


def sync_with_directory():
    """Synchronize the Chroma database with the current state of the data directory."""
    print("🔄 Connecting to Chroma for synchronization...")
    start_time = time.time()
    db = Chroma(
        persist_directory=CHROMA_PATH,
        embedding_function=OllamaEmbeddings(model=EMBEDDING_MODEL, base_url=OLLAMA_BASE_URL),
    )
    print(f"✅ Connected to Chroma in {time.time() - start_time:.2f} seconds.")

    existing_items = db.get(include=["metadatas"])
    existing_ids = set(existing_items["ids"])
    existing_sources = {item["source"] for item in existing_items["metadatas"]}

    
    current_files = set(os.path.join(DATA_PATH, f) for f in os.listdir(DATA_PATH) if f.endswith(".pdf"))
    current_sources = {os.path.abspath(file) for file in current_files}

    
    removed_sources = existing_sources - current_sources
    if removed_sources:
        print(f"🗑️ Removing {len(removed_sources)} documents from the database...")
        removed_ids = [
            doc["id"] for doc in existing_items["metadatas"] if doc["source"] in removed_sources
        ]
        db.delete(ids=removed_ids)

    
    renamed_files = detect_renamed_files(existing_sources, current_sources)
    if renamed_files:
        print(f"🔄 Updating {len(renamed_files)} renamed files in the database...")
        for old_source, new_source in renamed_files.items():
            update_source_in_db(db, old_source, new_source)


def detect_renamed_files(existing_sources: set, current_sources: set) -> dict:
    """Detect renamed files by comparing existing and current sources."""
    renamed_files = {}
    for source in existing_sources:
        if source not in current_sources:
            for new_source in current_sources:
                if os.path.basename(source) == os.path.basename(new_source):
                    renamed_files[source] = new_source
                    break
    return renamed_files


def update_source_in_db(db: Chroma, old_source: str, new_source: str):
    """Update the source metadata for renamed documents in the database."""
    existing_items = db.get(include=["metadatas"])
    for metadata in existing_items["metadatas"]:
        if metadata["source"] == old_source:
            doc_id = metadata["id"]
            updated_metadata = metadata.copy()
            updated_metadata["source"] = new_source
            db.update(ids=[doc_id], metadatas=[updated_metadata])


def add_to_chroma(chunks: List[Document]):
    print("🔄 Connecting to Chroma for adding chunks...")
    start_time = time.time()
    db = Chroma(
        persist_directory=CHROMA_PATH,
        embedding_function=OllamaEmbeddings(model=EMBEDDING_MODEL, base_url=OLLAMA_BASE_URL),
    )
    print(f"✅ Connected to Chroma in {time.time() - start_time:.2f} seconds.")

    BATCH_SIZE = 50
    chunks_with_ids = calculate_chunk_ids(chunks)
    existing_ids = set(db.get(include=[]).get("ids", []))
    new_chunks = [chunk for chunk in chunks_with_ids if chunk.metadata["id"] not in existing_ids]

    print(f"📂 Existing documents in database: {len(existing_ids)}")
    if new_chunks:
        print(f"👉 Adding {len(new_chunks)} new chunks in batches of {BATCH_SIZE}...")
        for i in range(0, len(new_chunks), BATCH_SIZE):
            batch = new_chunks[i:i + BATCH_SIZE]
            batch_start = time.time()
            db.add_documents(batch, ids=[chunk.metadata["id"] for chunk in batch])
            print(f"✅ Batch {i // BATCH_SIZE + 1} added in {time.time() - batch_start:.2f} seconds.")
    else:
        print("✅ No new chunks to add.")
    print(f"✅ All chunks added to Chroma in {time.time() - start_time:.2f} seconds.")


def calculate_chunk_ids(chunks: List[Document]) -> List[Document]:
    """Calculate unique IDs for each document chunk."""
    last_page_id = None
    current_chunk_index = 0

    for chunk in chunks:
        source = chunk.metadata.get("source")
        page = chunk.metadata.get("page")
        current_page_id = f"{source}:{page}"

        if current_page_id == last_page_id:
            current_chunk_index += 1
        else:
            current_chunk_index = 0
        chunk_id = f"{current_page_id}:{current_chunk_index}"
        last_page_id = current_page_id

        chunk.metadata["id"] = chunk_id

    return chunks


def clear_database():
    """Clear the Chroma database by deleting the persistence directory."""
    if os.path.exists(CHROMA_PATH):
        os.system(f"rm -rf {CHROMA_PATH}")
        print(f"🗑️ Cleared Chroma database at {CHROMA_PATH}")


if __name__ == "__main__":
    main()
