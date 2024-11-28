import os
import json
import subprocess
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler


with open("config.json", "r") as config_file:
    config = json.load(config_file)


DATA_PATH = os.getenv("DATA_PATH", config["data_path"])
PYTHON_PATH = os.getenv("PYTHON_PATH", config["python_path"])
POPULATE_DB_COMMAND = [PYTHON_PATH, "src/populate_database.py"]
SERVER_COMMAND = [PYTHON_PATH, "-m", "uvicorn", "src.fastapi_app:app", "--host", "0.0.0.0", "--port", "8000"]

server_process = None  


class DataChangeHandler(FileSystemEventHandler):
    """Handler to watch for changes in the data folder."""

    def on_any_event(self, event):
        if event.is_directory or event.event_type not in {"created", "modified", "deleted"}:
            return
        print(f"🔄 Detected change in data folder: {event.src_path}")
        restart_server()


def restart_server():
    """Restart the server process after updating the database."""
    global server_process

    
    if server_process:
        print("🛑 Stopping server due to data change...")
        server_process.terminate()
        server_process.wait()
        print("✅ Server stopped.")

    
    print("⚙️  Running populate_database.py to update the database...")
    try:
        subprocess.run(POPULATE_DB_COMMAND, check=True)
        print("✅ Database updated successfully.")
    except subprocess.CalledProcessError as e:
        print(f"❌ Error running populate_database.py: {e}")
        return

    
    print("🚀 Restarting server...")
    server_process = subprocess.Popen(SERVER_COMMAND)
    print("✅ Server restarted and running.")


def main():
    global server_process

    
    print("⚙️  Initializing database...")
    try:
        subprocess.run(POPULATE_DB_COMMAND, check=True)
        print("✅ Database initialized successfully.")
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to initialize database: {e}")
        return

    
    print("🚀 Starting server...")
    server_process = subprocess.Popen(SERVER_COMMAND)
    print("✅ Server is running.")

    
    print(f"👀 Monitoring changes in {DATA_PATH}...")
    event_handler = DataChangeHandler()
    observer = Observer()
    observer.schedule(event_handler, DATA_PATH, recursive=True)
    observer.start()

    
    try:
        observer.join()
    except KeyboardInterrupt:
        print("🛑 Shutting down due to keyboard interrupt...")
        observer.stop()
        if server_process:
            server_process.terminate()
        print("✅ Clean shutdown completed.")


if __name__ == "__main__":
    main()
