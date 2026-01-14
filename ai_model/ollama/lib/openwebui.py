"""
Open WebUI integration for local LLM setup.

Provides functions to:
- Check Docker installation
- Deploy Open WebUI container with 100% local configuration
- Configure Open WebUI to use Ollama models
- Manage container lifecycle (start, stop, status, remove)

Open WebUI is a self-hosted, offline-capable web interface for LLMs.
When configured with Ollama, it provides a ChatGPT-like experience
running entirely on your local machine.

Key features:
- 100% Local: No data leaves your machine
- Uses pulled GPT-OSS model from Ollama
- VPN-resilient: Uses 127.0.0.1 instead of localhost
- Optimized for Apple Silicon (Docker Desktop)
"""

import json
import os
import platform
import shutil
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from . import hardware
from . import ui
from . import utils
from .utils import get_unverified_ssl_context

# =============================================================================
# Configuration Constants
# =============================================================================

# Container configuration
OPENWEBUI_CONTAINER_NAME = "open-webui-local"
OPENWEBUI_IMAGE = "ghcr.io/open-webui/open-webui:main"
OPENWEBUI_PORT = 3000  # Default port for Open WebUI
OPENWEBUI_INTERNAL_PORT = 8080  # Internal container port

# Ollama connection (VPN-resilient - use host.docker.internal for Docker)
# On macOS/Windows Docker, host.docker.internal resolves to host machine
# On Linux, we need to use --network=host or specify the host IP
OLLAMA_HOST_DOCKER = "host.docker.internal"
OLLAMA_PORT = 11434

# Data volume for persistence
OPENWEBUI_DATA_VOLUME = "open-webui-data"

# Environment variables for 100% local operation
OPENWEBUI_ENV = {
    # Connect to local Ollama
    "OLLAMA_BASE_URL": f"http://{OLLAMA_HOST_DOCKER}:{OLLAMA_PORT}",
    # Disable telemetry for privacy
    "DO_NOT_TRACK": "true",
    "SCARF_NO_ANALYTICS": "true",
    # Disable external connections
    "ENABLE_SIGNUP": "false",  # Single user mode
    "WEBUI_AUTH": "false",  # No authentication for local use
    
    # =========================================================================
    # RAG (Retrieval-Augmented Generation) Configuration
    # Reference: https://docs.openwebui.com/tutorials/tips/rag-tutorial
    # =========================================================================
    
    # Embedding Engine - Use local Ollama for 100% offline operation
    "RAG_EMBEDDING_ENGINE": "ollama",
    "RAG_EMBEDDING_MODEL": "nomic-embed-text",
    "RAG_EMBEDDING_MODEL_AUTO_UPDATE": "true",
    "RAG_EMBEDDING_BATCH_SIZE": "256",  # Batch size for embedding generation
    
    # Ollama embedding endpoint (required for Ollama embedding engine)
    "RAG_OLLAMA_BASE_URL": f"http://{OLLAMA_HOST_DOCKER}:{OLLAMA_PORT}",
    
    # Chunk Configuration - Optimized for code and documentation
    # Larger chunks for better context, with overlap to maintain continuity
    "CHUNK_SIZE": "1500",  # Characters per chunk (good balance for code)
    "CHUNK_OVERLAP": "200",  # Overlap between chunks for context continuity
    
    # Retrieval Configuration
    "RAG_TOP_K": "5",  # Number of relevant chunks to retrieve
    "RAG_RELEVANCE_THRESHOLD": "0.0",  # Minimum relevance (0.0 = return all top_k)
    
    # Reranking - Use local Ollama model for reranking results
    "RAG_RERANKING_MODEL_AUTO_UPDATE": "true",
    
    # Document Processing
    "PDF_EXTRACT_IMAGES": "false",  # Disable image extraction for speed
    "CONTENT_EXTRACTION_ENGINE": "",  # Use default (Tika not needed for local)
    
    # RAG Template - How retrieved context is injected into prompts
    # Uses default template which works well with most models
    
    # Vector Database - Uses built-in ChromaDB (no external DB needed)
    # Data persisted in the Docker volume
    
    # =========================================================================
    # End RAG Configuration
    # =========================================================================
    
    # Disable web search and external features (100% local)
    "ENABLE_RAG_WEB_SEARCH": "false",
    "ENABLE_IMAGE_GENERATION": "false",
    
    # Performance optimizations
    "ENABLE_OLLAMA_API": "true",
    "OLLAMA_API_BASE_URL": f"http://{OLLAMA_HOST_DOCKER}:{OLLAMA_PORT}/api",
}

# Linux-specific: Use host network mode for Ollama access
LINUX_OPENWEBUI_ENV = {
    **OPENWEBUI_ENV,
    "OLLAMA_BASE_URL": f"http://127.0.0.1:{OLLAMA_PORT}",
    "OLLAMA_API_BASE_URL": f"http://127.0.0.1:{OLLAMA_PORT}/api",
    "RAG_OLLAMA_BASE_URL": f"http://127.0.0.1:{OLLAMA_PORT}",
}


# =============================================================================
# Docker Detection and Installation
# =============================================================================

def is_docker_installed() -> bool:
    """Check if Docker is installed and available."""
    docker_path = shutil.which("docker")
    return docker_path is not None


def is_docker_running() -> bool:
    """Check if Docker daemon is running."""
    if not is_docker_installed():
        return False
    
    code, stdout, stderr = utils.run_command(
        ["docker", "info"],
        timeout=10
    )
    return code == 0


def get_docker_version() -> Optional[str]:
    """Get Docker version string."""
    if not is_docker_installed():
        return None
    
    code, stdout, stderr = utils.run_command(
        ["docker", "--version"],
        timeout=5
    )
    if code == 0:
        return stdout.strip()
    return None


def check_docker() -> Tuple[bool, str]:
    """
    Check Docker installation and daemon status.
    
    Returns:
        Tuple of (is_ready, message)
    """
    ui.print_subheader("Checking Docker Installation")
    
    if not is_docker_installed():
        ui.print_error("Docker not found")
        ui.print_info("Docker is required for Open WebUI")
        print()
        ui.print_info("Installation options:")
        
        if platform.system() == "Darwin":
            ui.print_info("  • Docker Desktop for Mac: https://docs.docker.com/desktop/install/mac-install/")
            ui.print_info("  • Or via Homebrew: brew install --cask docker")
        elif platform.system() == "Linux":
            ui.print_info("  • Docker Engine: https://docs.docker.com/engine/install/")
            ui.print_info("  • Or your package manager: apt install docker.io / dnf install docker")
        else:
            ui.print_info("  • Docker Desktop: https://docs.docker.com/desktop/install/windows-install/")
        
        return False, "Docker not installed"
    
    version = get_docker_version()
    ui.print_success(f"Docker installed: {version}")
    
    if not is_docker_running():
        ui.print_warning("Docker daemon is not running")
        
        if platform.system() == "Darwin":
            ui.print_info("Please start Docker Desktop application")
            ui.print_info("You can find it in Applications or the menu bar")
            
            if ui.prompt_yes_no("Would you like to try starting Docker Desktop?", default=True):
                success = start_docker_desktop_macos()
                if success:
                    ui.print_success("Docker Desktop started")
                    return True, "Docker ready"
                else:
                    return False, "Could not start Docker Desktop"
        elif platform.system() == "Linux":
            ui.print_info("Start Docker with: sudo systemctl start docker")
        else:
            ui.print_info("Please start Docker Desktop application")
        
        return False, "Docker not running"
    
    ui.print_success("Docker daemon is running")
    return True, "Docker ready"


def start_docker_desktop_macos() -> bool:
    """Attempt to start Docker Desktop on macOS."""
    if platform.system() != "Darwin":
        return False
    
    ui.print_info("Starting Docker Desktop...")
    
    # Try to open Docker Desktop
    code, _, _ = utils.run_command(
        ["open", "-a", "Docker"],
        timeout=10
    )
    
    if code != 0:
        ui.print_warning("Could not start Docker Desktop automatically")
        return False
    
    # Wait for Docker daemon to be ready
    ui.print_info("Waiting for Docker daemon to start...")
    for attempt in range(30):  # Wait up to 30 seconds
        time.sleep(1)
        if is_docker_running():
            return True
        if attempt % 5 == 4:
            ui.print_info("Still waiting for Docker...")
    
    ui.print_warning("Docker Desktop started but daemon not ready")
    ui.print_info("Please wait a moment and try again")
    return False


# =============================================================================
# Open WebUI Container Management
# =============================================================================

def is_openwebui_container_exists() -> bool:
    """Check if Open WebUI container exists (running or stopped)."""
    if not is_docker_running():
        return False
    
    code, stdout, _ = utils.run_command(
        ["docker", "ps", "-a", "--filter", f"name={OPENWEBUI_CONTAINER_NAME}", "--format", "{{.Names}}"],
        timeout=10
    )
    return code == 0 and OPENWEBUI_CONTAINER_NAME in stdout


def is_openwebui_running() -> bool:
    """Check if Open WebUI container is running."""
    if not is_docker_running():
        return False
    
    code, stdout, _ = utils.run_command(
        ["docker", "ps", "--filter", f"name={OPENWEBUI_CONTAINER_NAME}", "--format", "{{.Names}}"],
        timeout=10
    )
    return code == 0 and OPENWEBUI_CONTAINER_NAME in stdout


def get_openwebui_status() -> Dict[str, Any]:
    """
    Get Open WebUI container status.
    
    Returns:
        Dict with status information
    """
    status = {
        "docker_installed": is_docker_installed(),
        "docker_running": False,
        "container_exists": False,
        "container_running": False,
        "container_port": None,
        "web_accessible": False,
        "url": None,
    }
    
    if not status["docker_installed"]:
        return status
    
    status["docker_running"] = is_docker_running()
    if not status["docker_running"]:
        return status
    
    status["container_exists"] = is_openwebui_container_exists()
    if not status["container_exists"]:
        return status
    
    status["container_running"] = is_openwebui_running()
    
    # Get port mapping
    if status["container_running"]:
        code, stdout, _ = utils.run_command(
            ["docker", "port", OPENWEBUI_CONTAINER_NAME, str(OPENWEBUI_INTERNAL_PORT)],
            timeout=5
        )
        if code == 0 and stdout.strip():
            # Parse port mapping (e.g., "0.0.0.0:3000")
            port_mapping = stdout.strip().split(":")[-1]
            try:
                status["container_port"] = int(port_mapping)
            except ValueError:
                status["container_port"] = OPENWEBUI_PORT
        else:
            status["container_port"] = OPENWEBUI_PORT
        
        status["url"] = f"http://localhost:{status['container_port']}"
        
        # Check if web interface is accessible
        status["web_accessible"] = verify_openwebui_accessible(status["container_port"])
    
    return status


def verify_openwebui_accessible(port: int = OPENWEBUI_PORT) -> bool:
    """Check if Open WebUI web interface is accessible."""
    try:
        req = urllib.request.Request(
            f"http://127.0.0.1:{port}/",
            method="GET"
        )
        with urllib.request.urlopen(req, timeout=5, context=get_unverified_ssl_context()) as response:
            return response.status == 200
    except Exception:
        return False


def pull_openwebui_image() -> bool:
    """Pull the Open WebUI Docker image."""
    ui.print_info(f"Pulling Open WebUI image: {OPENWEBUI_IMAGE}")
    ui.print_info("This may take a few minutes on first run...")
    
    code, stdout, stderr = utils.run_command(
        ["docker", "pull", OPENWEBUI_IMAGE],
        timeout=600  # 10 minutes for large image
    )
    
    if code != 0:
        ui.print_error(f"Failed to pull image: {stderr}")
        return False
    
    ui.print_success("Open WebUI image pulled successfully")
    return True


def create_openwebui_container(
    port: int = OPENWEBUI_PORT,
    hw_info: Optional[hardware.HardwareInfo] = None
) -> bool:
    """
    Create and start the Open WebUI container.
    
    Args:
        port: Host port to map to (default: 3000)
        hw_info: Hardware info for optimizations
    
    Returns:
        True if container created successfully
    """
    # Determine environment based on OS
    is_linux = platform.system() == "Linux"
    env_vars = LINUX_OPENWEBUI_ENV if is_linux else OPENWEBUI_ENV
    
    # Build docker run command
    cmd = [
        "docker", "run", "-d",
        "--name", OPENWEBUI_CONTAINER_NAME,
        "-p", f"{port}:{OPENWEBUI_INTERNAL_PORT}",
        "-v", f"{OPENWEBUI_DATA_VOLUME}:/app/backend/data",
        "--restart", "unless-stopped",  # Auto-restart on boot
    ]
    
    # Add environment variables
    for key, value in env_vars.items():
        cmd.extend(["-e", f"{key}={value}"])
    
    # Linux-specific: Use host network for Ollama access
    # This allows the container to access localhost services
    if is_linux:
        cmd.append("--add-host=host.docker.internal:host-gateway")
    
    # Add the image
    cmd.append(OPENWEBUI_IMAGE)
    
    ui.print_info("Creating Open WebUI container...")
    
    code, stdout, stderr = utils.run_command(cmd, timeout=60)
    
    if code != 0:
        ui.print_error(f"Failed to create container: {stderr}")
        return False
    
    ui.print_success("Open WebUI container created")
    
    # Wait for container to be ready
    ui.print_info("Waiting for Open WebUI to start...")
    for attempt in range(30):  # Wait up to 30 seconds
        time.sleep(1)
        if verify_openwebui_accessible(port):
            ui.print_success("Open WebUI is ready!")
            return True
        if attempt % 5 == 4:
            ui.print_info("Still starting up...")
    
    # Check if container is still running
    if is_openwebui_running():
        ui.print_warning("Container is running but web interface not yet accessible")
        ui.print_info("It may take a moment longer to fully start")
        return True
    else:
        ui.print_error("Container stopped unexpectedly")
        # Show container logs
        code, logs, _ = utils.run_command(
            ["docker", "logs", "--tail", "20", OPENWEBUI_CONTAINER_NAME],
            timeout=10
        )
        if code == 0 and logs:
            ui.print_info("Container logs:")
            print(logs)
        return False


def start_openwebui_container() -> bool:
    """Start an existing Open WebUI container."""
    if not is_openwebui_container_exists():
        ui.print_error("Open WebUI container does not exist")
        return False
    
    if is_openwebui_running():
        ui.print_info("Open WebUI is already running")
        return True
    
    ui.print_info("Starting Open WebUI container...")
    
    code, _, stderr = utils.run_command(
        ["docker", "start", OPENWEBUI_CONTAINER_NAME],
        timeout=30
    )
    
    if code != 0:
        ui.print_error(f"Failed to start container: {stderr}")
        return False
    
    # Wait for container to be accessible
    for attempt in range(15):
        time.sleep(1)
        if verify_openwebui_accessible():
            ui.print_success("Open WebUI started")
            return True
    
    if is_openwebui_running():
        ui.print_warning("Container is running but web interface not yet accessible")
        return True
    
    return False


def stop_openwebui_container() -> bool:
    """Stop the Open WebUI container."""
    if not is_openwebui_running():
        ui.print_info("Open WebUI is not running")
        return True
    
    ui.print_info("Stopping Open WebUI container...")
    
    code, _, stderr = utils.run_command(
        ["docker", "stop", OPENWEBUI_CONTAINER_NAME],
        timeout=30
    )
    
    if code != 0:
        ui.print_error(f"Failed to stop container: {stderr}")
        return False
    
    ui.print_success("Open WebUI stopped")
    return True


def remove_openwebui_container(remove_data: bool = False) -> bool:
    """
    Remove the Open WebUI container and optionally its data.
    
    Args:
        remove_data: If True, also remove the data volume
    
    Returns:
        True if removal successful
    """
    # Stop container first if running
    if is_openwebui_running():
        stop_openwebui_container()
    
    # Remove container
    if is_openwebui_container_exists():
        ui.print_info("Removing Open WebUI container...")
        
        code, _, stderr = utils.run_command(
            ["docker", "rm", OPENWEBUI_CONTAINER_NAME],
            timeout=30
        )
        
        if code != 0:
            ui.print_error(f"Failed to remove container: {stderr}")
            return False
        
        ui.print_success("Container removed")
    else:
        ui.print_info("Container already removed")
    
    # Remove data volume if requested
    if remove_data:
        ui.print_info("Removing Open WebUI data volume...")
        
        code, _, stderr = utils.run_command(
            ["docker", "volume", "rm", OPENWEBUI_DATA_VOLUME],
            timeout=30
        )
        
        if code == 0:
            ui.print_success("Data volume removed")
        else:
            # Volume might not exist or be in use
            ui.print_warning(f"Could not remove data volume: {stderr}")
    
    return True


def remove_openwebui_image() -> bool:
    """Remove the Open WebUI Docker image."""
    ui.print_info("Removing Open WebUI image...")
    
    code, _, stderr = utils.run_command(
        ["docker", "rmi", OPENWEBUI_IMAGE],
        timeout=60
    )
    
    if code == 0:
        ui.print_success("Image removed")
        return True
    else:
        ui.print_warning(f"Could not remove image: {stderr}")
        return False


# =============================================================================
# Setup and Configuration
# =============================================================================

def setup_openwebui(
    hw_info: hardware.HardwareInfo,
    port: int = OPENWEBUI_PORT
) -> Tuple[bool, Optional[str]]:
    """
    Set up Open WebUI with 100% local configuration.
    
    Args:
        hw_info: Hardware information
        port: Port to run Open WebUI on
    
    Returns:
        Tuple of (success, url)
    """
    ui.print_header("🌐 Open WebUI Setup")
    
    ui.print_info("Open WebUI provides a ChatGPT-like interface for your local LLM")
    ui.print_info("All data stays on your machine - 100% private and offline-capable")
    print()
    
    # Check Docker
    docker_ready, docker_msg = check_docker()
    if not docker_ready:
        return False, None
    
    # Check if container already exists
    if is_openwebui_container_exists():
        ui.print_info("Open WebUI container already exists")
        
        if is_openwebui_running():
            url = f"http://localhost:{port}"
            ui.print_success(f"Open WebUI is running at: {url}")
            return True, url
        else:
            if ui.prompt_yes_no("Start existing Open WebUI container?", default=True):
                if start_openwebui_container():
                    url = f"http://localhost:{port}"
                    return True, url
                return False, None
            else:
                if ui.prompt_yes_no("Remove existing container and create new one?", default=False):
                    remove_openwebui_container()
                else:
                    return False, None
    
    # Pull image
    print()
    ui.print_subheader("Downloading Open WebUI")
    if not pull_openwebui_image():
        return False, None
    
    # Create container
    print()
    ui.print_subheader("Creating Open WebUI Container")
    
    ui.print_info("Configuration:")
    print(f"  • Port: {port}")
    print(f"  • Ollama connection: {OPENWEBUI_ENV['OLLAMA_BASE_URL']}")
    print(f"  • Privacy mode: Enabled (no telemetry)")
    print(f"  • Auto-restart: Enabled")
    print()
    ui.print_info("RAG (Document Q&A) Configuration:")
    print(f"  • Embedding model: {OPENWEBUI_ENV['RAG_EMBEDDING_MODEL']} (local)")
    print(f"  • Chunk size: {OPENWEBUI_ENV['CHUNK_SIZE']} chars")
    print(f"  • Chunk overlap: {OPENWEBUI_ENV['CHUNK_OVERLAP']} chars")
    print(f"  • Top-K results: {OPENWEBUI_ENV['RAG_TOP_K']}")
    print(f"  • Vector DB: ChromaDB (built-in, persisted)")
    print()
    
    if create_openwebui_container(port=port, hw_info=hw_info):
        url = f"http://localhost:{port}"
        return True, url
    
    return False, None


def configure_openwebui_model(model_name: str = "gpt-oss:20b") -> bool:
    """
    Configure Open WebUI to use a specific model as default.
    
    Note: Open WebUI auto-discovers models from Ollama, but this can
    set a preferred default model.
    
    Args:
        model_name: Ollama model name to set as default
    
    Returns:
        True if configuration successful
    """
    # Open WebUI auto-discovers models from Ollama
    # The user can select the model in the UI
    # This function is for future API-based configuration
    ui.print_info(f"Open WebUI will auto-discover models from Ollama")
    ui.print_info(f"Recommended model: {model_name}")
    return True


# =============================================================================
# Next Steps and Documentation
# =============================================================================

def show_openwebui_next_steps(url: str, model_name: str = "gpt-oss:20b") -> None:
    """Display next steps after Open WebUI setup."""
    print()
    print(ui.colorize("━" * 60, ui.Colors.DIM))
    print(ui.colorize("🌐 Open WebUI Setup Complete!", ui.Colors.GREEN + ui.Colors.BOLD))
    print()
    
    print(ui.colorize("Access your local ChatGPT-like interface:", ui.Colors.BLUE))
    print()
    print(f"  URL: {ui.colorize(url, ui.Colors.CYAN + ui.Colors.BOLD)}")
    print()
    
    print(ui.colorize("First-time setup:", ui.Colors.YELLOW + ui.Colors.BOLD))
    print()
    print("  1. Open the URL above in your browser")
    print("  2. Create a local admin account (stored only on your machine)")
    print(f"  3. Select '{model_name}' from the model dropdown")
    print("  4. Start chatting with your local AI!")
    print()
    
    print(ui.colorize("Features available:", ui.Colors.BLUE))
    print()
    print("  • 💬 Chat with GPT-OSS 20B (matches o3-mini performance)")
    print("  • 📁 Upload files for analysis (stays local)")
    print("  • 🔍 RAG: Index documents for Q&A (see below)")
    print("  • 💾 Conversation history (stored locally)")
    print("  • 🎨 Multiple chat sessions")
    print()
    
    # RAG Documentation Section
    print(ui.colorize("━" * 60, ui.Colors.DIM))
    print(ui.colorize("📚 RAG (Retrieval-Augmented Generation) Guide:", ui.Colors.YELLOW + ui.Colors.BOLD))
    print()
    print(ui.colorize("  What is RAG?", ui.Colors.BLUE))
    print("    RAG lets you chat with your documents. Upload PDFs, code files,")
    print("    or text documents and ask questions about their content.")
    print("    The AI retrieves relevant sections and answers based on them.")
    print()
    
    print(ui.colorize("  How to use RAG:", ui.Colors.BLUE))
    print()
    print("  1️⃣  Create a Knowledge Base:")
    print("      • Click 'Workspace' → 'Knowledge' in the sidebar")
    print("      • Click '+ Create Knowledge' button")
    print("      • Give it a name (e.g., 'Project Docs')")
    print()
    print("  2️⃣  Add Documents:")
    print("      • Click on your knowledge base")
    print("      • Drag & drop files or click to upload")
    print("      • Supported: PDF, TXT, MD, DOCX, code files")
    print("      • Documents are chunked and embedded locally")
    print()
    print("  3️⃣  Chat with Documents:")
    print("      • Start a new chat")
    print("      • Click the '#' icon to select your knowledge base")
    print("      • Ask questions about your documents!")
    print()
    
    print(ui.colorize("  RAG Configuration (pre-configured):", ui.Colors.BLUE))
    print(f"    • Embedding model: nomic-embed-text (local Ollama)")
    print(f"    • Chunk size: {OPENWEBUI_ENV['CHUNK_SIZE']} characters")
    print(f"    • Chunk overlap: {OPENWEBUI_ENV['CHUNK_OVERLAP']} characters")
    print(f"    • Top-K results: {OPENWEBUI_ENV['RAG_TOP_K']} chunks retrieved")
    print(f"    • Vector DB: ChromaDB (built-in, no setup needed)")
    print()
    
    print(ui.colorize("  Pro tips:", ui.Colors.GREEN))
    print("    • Smaller, focused documents work better than huge files")
    print("    • Use descriptive filenames for better organization")
    print("    • You can create multiple knowledge bases for different topics")
    print("    • Adjust settings in Admin Panel → Settings → Documents if needed")
    print()
    
    print(ui.colorize("━" * 60, ui.Colors.DIM))
    print(ui.colorize("Privacy & Security:", ui.Colors.GREEN + ui.Colors.BOLD))
    print()
    print("  • ✅ 100% local - no data sent to external servers")
    print("  • ✅ Telemetry disabled")
    print("  • ✅ Works offline after initial setup")
    print("  • ✅ All data stored in Docker volume on your machine")
    print("  • ✅ Embeddings generated locally with nomic-embed-text")
    print()
    
    print(ui.colorize("Container management:", ui.Colors.BLUE))
    print()
    print("  Stop:    docker stop open-webui-local")
    print("  Start:   docker start open-webui-local")
    print("  Logs:    docker logs open-webui-local")
    print("  Remove:  docker rm -f open-webui-local")
    print()
    
    print(ui.colorize("Documentation:", ui.Colors.BLUE))
    print()
    print("  • Open WebUI Docs: https://docs.openwebui.com")
    print("  • RAG Tutorial: https://docs.openwebui.com/tutorials/tips/rag-tutorial")
    print()
    
    print(ui.colorize("━" * 60, ui.Colors.DIM))


def display_openwebui_status() -> None:
    """Display current Open WebUI status."""
    status = get_openwebui_status()
    
    ui.print_subheader("Open WebUI Status")
    
    if not status["docker_installed"]:
        ui.print_error("Docker is not installed")
        return
    
    if not status["docker_running"]:
        ui.print_warning("Docker daemon is not running")
        return
    
    if not status["container_exists"]:
        ui.print_info("Open WebUI container is not installed")
        ui.print_info("Run the setup to create it")
        return
    
    if status["container_running"]:
        ui.print_success("Open WebUI is running")
        if status["url"]:
            ui.print_info(f"URL: {status['url']}")
        if status["web_accessible"]:
            ui.print_success("Web interface is accessible")
        else:
            ui.print_warning("Web interface not responding (may be starting up)")
    else:
        ui.print_warning("Open WebUI container exists but is not running")
        ui.print_info("Start it with: docker start open-webui-local")


# =============================================================================
# Uninstall Support
# =============================================================================

def uninstall_openwebui(remove_data: bool = True, remove_image: bool = False) -> Dict[str, bool]:
    """
    Uninstall Open WebUI.
    
    Args:
        remove_data: Remove the data volume (chat history, settings)
        remove_image: Remove the Docker image
    
    Returns:
        Dict with removal status for each component
    """
    results = {
        "container_removed": False,
        "data_removed": False,
        "image_removed": False,
    }
    
    ui.print_subheader("Uninstalling Open WebUI")
    
    if not is_docker_installed():
        ui.print_warning("Docker is not installed - nothing to uninstall")
        return results
    
    if not is_docker_running():
        ui.print_warning("Docker daemon is not running")
        ui.print_info("Please start Docker to complete uninstallation")
        return results
    
    # Remove container
    if is_openwebui_container_exists():
        results["container_removed"] = remove_openwebui_container(remove_data=remove_data)
        results["data_removed"] = remove_data and results["container_removed"]
    else:
        ui.print_info("Container already removed")
        results["container_removed"] = True
    
    # Remove image if requested
    if remove_image:
        results["image_removed"] = remove_openwebui_image()
    
    return results


def get_openwebui_manifest_entry() -> Dict[str, Any]:
    """
    Get manifest entry for Open WebUI installation.
    
    Returns:
        Dict with installation details for manifest
    """
    from datetime import datetime, timezone
    
    status = get_openwebui_status()
    
    return {
        "type": "openwebui",
        "installed": status["container_exists"],
        "running": status["container_running"],
        "container_name": OPENWEBUI_CONTAINER_NAME,
        "image": OPENWEBUI_IMAGE,
        "port": status.get("container_port", OPENWEBUI_PORT),
        "data_volume": OPENWEBUI_DATA_VOLUME,
        "url": status.get("url"),
        "installed_at": datetime.now(timezone.utc).isoformat() if status["container_exists"] else None,
    }
