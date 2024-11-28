param (
    [string]$Service = "all",
    [string]$Mode = "online"
)

$FastApiDockerfile = "Dockerfile.fastapi"
$OllamaDockerfile = "Dockerfile.ollama"
$FastApiImageName = "fastapi-server:latest"
$OllamaImageName = "ollama-server:latest"
$FastApiImageTar = "docker/fastapi-server.tar"
$OllamaImageTar = "docker/ollama-server.tar"
$DockerDirectory = "docker"
$DataDirectory = "data"


if (-not (Test-Path $DockerDirectory)) {
    Write-Output "Creating $DockerDirectory directory..."
    try {
        New-Item -ItemType Directory -Path $DockerDirectory | Out-Null
        Write-Output "$DockerDirectory directory created successfully."
    } catch {
        Write-Error "Error: Failed to create $DockerDirectory directory. Exception: $_"
        exit 1
    }
} else {
    Write-Output "$DockerDirectory directory already exists."
}


if (-not (Test-Path $DataDirectory)) {
    Write-Output "Creating $DataDirectory directory..."
    try {
        New-Item -ItemType Directory -Path $DataDirectory | Out-Null
        Write-Output "$DataDirectory directory created successfully."
    } catch {
        Write-Error "Error: Failed to create $DataDirectory directory. Exception: $_"
        exit 1
    }
} else {
    Write-Output "$DataDirectory directory already exists."
}

Write-Output "Service: $Service"
Write-Output "Mode: $Mode"

function CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
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

function BuildImage {
    param (
        [string]$Dockerfile,
        [string]$ImageName
    )
    Write-Output "DEBUG: Inspecting image $ImageName before build..."
    $beforeBuildId = docker inspect --format="{{.Id}}" $ImageName 2>$null
    if ($LASTEXITCODE -eq 0 -and $beforeBuildId) {
        Write-Output "DEBUG: Image ID before build: $beforeBuildId"
    } else {
        Write-Output "DEBUG: Image does not exist before build."
    }

    Write-Output "Building Docker image: $ImageName using $Dockerfile..."
    VerifyFile -FilePath $Dockerfile -FileDescription "Dockerfile for $ImageName"
    try {
        docker build -f $Dockerfile -t $ImageName .
        if ($LASTEXITCODE -ne 0) {
            throw "Build failed for $ImageName."
        }
    } catch {
        Write-Error "Error: Failed to build Docker image $ImageName. Exception: $_"
        exit 1
    }

    Write-Output "DEBUG: Inspecting image $ImageName after build..."
    $afterBuildId = docker inspect --format="{{.Id}}" $ImageName 2>$null
    if ($LASTEXITCODE -eq 0 -and $afterBuildId) {
        Write-Output "DEBUG: Image ID after build: $afterBuildId"
    } else {
        Write-Error "Error: Failed to retrieve image ID after build for $ImageName."
        exit 1
    }

    if ($beforeBuildId -and $afterBuildId -and $beforeBuildId -ne $afterBuildId) {
        Write-Output "DEBUG: Image ID has changed. The image has been updated."
        return 1
    } elseif ($beforeBuildId -and $afterBuildId -and $beforeBuildId -eq $afterBuildId) {
        Write-Output "DEBUG: Image ID has not changed. No update to the image."
        return 0
    } else {
        Write-Error "Error: Unable to determine if the image has changed."
        exit 1
    }
}

function SaveImage {
    param (
        [string]$ImageName,
        [string]$ImageTar
    )
    Write-Output "Saving image $ImageName to $ImageTar..."
    try {
        docker save -o $ImageTar $ImageName
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to save image $ImageName."
        }
    } catch {
        Write-Error "Error: Failed to save Docker image $ImageName. Exception: $_"
        exit 1
    }
    Write-Output "Successfully saved Docker image: $ImageName to $ImageTar."
}

function LoadImage {
    param (
        [string]$ImageTar
    )
    Write-Output "Loading Docker image from $ImageTar..."
    VerifyFile -FilePath $ImageTar -FileDescription "Docker image tar file"
    try {
        docker load -i $ImageTar
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to load image from $ImageTar."
        }
    } catch {
        Write-Error "Error: Failed to load Docker image from $ImageTar. Exception: $_"
        exit 1
    }
    Write-Output "Successfully loaded Docker image from $ImageTar."
}

function ComposeService {
    param (
        [string]$ServiceName = "all"
    )
    Write-Output "Starting service(s) with Docker Compose..."
    try {
        if ($ServiceName -eq "all") {
            docker-compose up -d
        } else {
            docker-compose up -d $ServiceName
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to start service(s) with Docker Compose."
        }
    } catch {
        Write-Error "Error: Failed to start service(s) with Docker Compose. Exception: $_"
        exit 1
    }
    Write-Output "Successfully started service(s) with Docker Compose."
}

if (-not (CommandExists "docker")) {
    Write-Error "Error: Docker is not installed or not in PATH."
    exit 1
}

if (-not (CommandExists "docker-compose")) {
    Write-Error "Error: Docker Compose is not installed or not in PATH."
    exit 1
}

if ($Mode -eq "online") {
    if ($Service -eq "fastapi") {
        Write-Output "Processing FastAPI service in online mode..."
        Write-Output "Building $FastApiImageName..."
        $fastApiBuildStatus = BuildImage -Dockerfile $FastApiDockerfile -ImageName $FastApiImageName
        if ($fastApiBuildStatus -eq 1) {
            SaveImage -ImageName $FastApiImageName -ImageTar $FastApiImageTar
        } else {
            Write-Output "No changes detected for FastAPI image. Skipping save."
        }
        ComposeService -ServiceName "fastapi-server"
    }
    if ($Service -eq "ollama") {
        Write-Output "Processing Ollama service in online mode..."
        Write-Output "Building $OllamaImageName..."
        $ollamaBuildStatus = BuildImage -Dockerfile $OllamaDockerfile -ImageName $OllamaImageName
        if ($ollamaBuildStatus -eq 1) {
            SaveImage -ImageName $OllamaImageName -ImageTar $OllamaImageTar
        } else {
            Write-Output "No changes detected for Ollama image. Skipping save."
        }
        ComposeService -ServiceName "ollama-server"
    }
    if ($Service -eq "all") {
        Write-Output "Processing all services in online mode..."
        Write-Output "Building $FastApiImageName..."
        $fastApiBuildStatus = BuildImage -Dockerfile $FastApiDockerfile -ImageName $FastApiImageName
        if ($fastApiBuildStatus -eq 1) {
            SaveImage -ImageName $FastApiImageName -ImageTar $FastApiImageTar
        } else {
            Write-Output "No changes detected for FastAPI image. Skipping save."
        }
        Write-Output "Building $OllamaImageName..."
        $ollamaBuildStatus = BuildImage -Dockerfile $OllamaDockerfile -ImageName $OllamaImageName
        if ($ollamaBuildStatus -eq 1) {
            SaveImage -ImageName $OllamaImageName -ImageTar $OllamaImageTar
        } else {
            Write-Output "No changes detected for Ollama image. Skipping save."
        }
        ComposeService
    }
} elseif ($Mode -eq "offline") {
    if ($Service -eq "fastapi") {
        Write-Output "Processing FastAPI service in offline mode..."
        LoadImage -ImageTar $FastApiImageTar
        ComposeService -ServiceName "fastapi-server"
    }
    if ($Service -eq "ollama") {
        Write-Output "Processing Ollama service in offline mode..."
        LoadImage -ImageTar $OllamaImageTar
        ComposeService -ServiceName "ollama-server"
    }
    if ($Service -eq "all") {
        Write-Output "Processing all services in offline mode..."
        LoadImage -ImageTar $FastApiImageTar
        LoadImage -ImageTar $OllamaImageTar
        ComposeService
    }
} else {
    Write-Error "Invalid mode: $Mode. Use 'online' or 'offline'."
    exit 1
}

Write-Output "Operation completed successfully!"
if ($Service -eq "all" -or $Service -eq "fastapi") {
    Write-Output "FastAPI server is running on http://localhost:8000"
}
if ($Service -eq "all" -or $Service -eq "ollama") {
    Write-Output "Ollama server is running on http://localhost:11434"
}
