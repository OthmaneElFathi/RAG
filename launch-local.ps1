# launch-local.ps1

# Configuration
$ConfigFile = "config.json"
$VenvPath = "venv"
$RequirementsFile = "requirements.txt"
$WatcherScript = "src/watcher.py"

# Function to check if a command exists
function CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# Function to check if a Python virtual environment exists
function VerifyPythonEnvironment {
    if (-not (Test-Path $VenvPath)) {
        Write-Error "Error: Python virtual environment not found at $VenvPath."
        exit 1
    }
    Write-Output "Python virtual environment found at $VenvPath."
}

# Function to check if a file exists
function VerifyFile {
    param (
        [string]$FilePath,
        [string]$FileDescription
    )
    Write-Output "Verifying presence of $FileDescription at $FilePath..."
    if (-not (Test-Path $FilePath)) {
        Write-Error "Error: $FileDescription not found at $FilePath."
        exit 1
    }
    Write-Output "$FileDescription found."
}

# Step 1: Check if Ollama is installed
Write-Output "Checking if Ollama is installed..."
if (-not (CommandExists "ollama")) {
    Write-Error "Error: Ollama is not installed or not in PATH."
    exit 1
}
Write-Output "Ollama is installed."

# Step 2: Check if models exist in Ollama
Write-Output "Checking models in Ollama..."
if (-not (Test-Path $ConfigFile)) {
    Write-Error "Error: Configuration file $ConfigFile not found."
    exit 1
}

$config = Get-Content $ConfigFile | ConvertFrom-Json
$EmbeddingModel = $config.models.embedding_model
$LlamaModel = $config.models.llama_model

if (-not $EmbeddingModel -or -not $LlamaModel) {
    Write-Error "Error: embedding_model or llama_model is not defined in $ConfigFile."
    exit 1
}

# Fetch and parse Ollama models
$OllamaList = ollama list | Select-String -Pattern "^(.*?)\s+.*$" | ForEach-Object { ($_ -split '\s+')[0] -replace ":[^:]+$", "" }
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error: Failed to fetch Ollama models."
    exit 1
}
Write-Output "Found models in Ollama (tags removed): $($OllamaList -join ', ')"

if ($OllamaList -notcontains $EmbeddingModel) {
    Write-Error "Error: Embedding model '$EmbeddingModel' not found in Ollama."
    exit 1
}
if ($OllamaList -notcontains $LlamaModel) {
    Write-Error "Error: Llama model '$LlamaModel' not found in Ollama."
    exit 1
}
Write-Output "Required models are available in Ollama."

# Step 3: Verify Python environment
Write-Output "Checking Python virtual environment..."
VerifyPythonEnvironment

# Step 4: Install dependencies
Write-Output "Installing dependencies..."
VerifyFile -FilePath $RequirementsFile -FileDescription "Requirements file"
& "$VenvPath\Scripts\python.exe" -m pip install -r $RequirementsFile
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error: Failed to install Python dependencies."
    exit 1
}
Write-Output "Dependencies installed successfully."

# Step 5: Run the watcher script
Write-Output "Starting the watcher script..."
VerifyFile -FilePath $WatcherScript -FileDescription "Watcher script"
& "$VenvPath\Scripts\python.exe" $WatcherScript
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error: Failed to start the watcher script."
    exit 1
}
Write-Output "Watcher script started successfully."
