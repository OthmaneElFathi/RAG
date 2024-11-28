$ConfigFile = "config.json"
$VenvPath = "venv"
$RequirementsFile = "requirements.txt"
$WatcherScript = "src/watcher.py"
$DataFolder = "data"


function CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}


function EnsureFolder {
    param([string]$FolderPath, [string]$FolderDescription)
    Write-Output "Ensuring $FolderDescription exists at $FolderPath..."
    if (-not (Test-Path $FolderPath)) {
        New-Item -ItemType Directory -Path $FolderPath | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Error: Failed to create $FolderDescription at $FolderPath."
            exit 1
        }
        Write-Output "$FolderDescription created successfully."
    } else {
        Write-Output "$FolderDescription already exists at $FolderPath."
    }
}


function EnsurePythonEnvironment {
    if (-not (Test-Path $VenvPath)) {
        Write-Output "Virtual environment not found. Creating a new one at $VenvPath..."
        & python -m venv $VenvPath
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Error: Failed to create Python virtual environment."
            exit 1
        }
        Write-Output "Virtual environment created successfully."
    } else {
        Write-Output "Python virtual environment already exists at $VenvPath."
    }
}


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


EnsureFolder -FolderPath $DataFolder -FolderDescription "data folder"


Write-Output "Checking if Ollama is installed..."
if (-not (CommandExists "ollama")) {
    Write-Error "Error: Ollama is not installed or not in PATH."
    exit 1
}
Write-Output "Ollama is installed."


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


Write-Output "Ensuring Python virtual environment..."
EnsurePythonEnvironment


Write-Output "Installing dependencies..."
VerifyFile -FilePath $RequirementsFile -FileDescription "Requirements file"
& "$VenvPath\Scripts\python.exe" -m pip install --upgrade pip
& "$VenvPath\Scripts\python.exe" -m pip install -r $RequirementsFile
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error: Failed to install Python dependencies."
    exit 1
}
Write-Output "Dependencies installed successfully."


Write-Output "Starting the watcher script..."
VerifyFile -FilePath $WatcherScript -FileDescription "Watcher script"
& "$VenvPath\Scripts\python.exe" $WatcherScript
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error: Failed to start the watcher script."
    exit 1
}
Write-Output "Watcher script started successfully."
