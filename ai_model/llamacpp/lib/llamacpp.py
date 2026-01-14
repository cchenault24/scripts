"""
Llama.cpp server management.

Provides functions to download, install, configure, and manage llama.cpp server
for macOS Apple Silicon systems with GPT-OSS 20B model.
"""

import json
import os
import platform
import plistlib
import shutil
import subprocess
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from . import hardware
from . import ui
from . import utils

# Configuration constants
LLAMACPP_BIN_DIR = Path.home() / "ai_models" / "llamacpp" / "bin"
LLAMACPP_MODEL_DIR = Path.home() / "ai_models" / "models"
LLAMACPP_LOG_DIR = Path.home() / "Library" / "Logs" / "llamacpp"
LLAMACPP_CACHE_DIR = Path.home() / "Library" / "Caches" / "llamacpp"

# Default configuration
DEFAULT_PORT = 8080
DEFAULT_HOST = "127.0.0.1"
DEFAULT_MODEL = "gpt-oss-20b-q4_k_m.gguf"
DEFAULT_QUANTIZATION = "Q4_K_M"

# Model information
GPT_OSS_20B_MODELS = {
    "Q4_K_M": {
        "name": "gpt-oss-20b-q4_k_m.gguf",
        "size_gb": 12.0,
        "sha256": None,  # Will be fetched from HuggingFace
    },
    "Q6_K_XL": {
        "name": "gpt-oss-20b-q6_k_xl.gguf",
        "size_gb": 15.0,
        "sha256": None,
    },
    "Q8_K_XL": {
        "name": "gpt-oss-20b-q8_k_xl.gguf",
        "size_gb": 18.0,
        "sha256": None,
    },
}

# Context size tiers by RAM
CONTEXT_TIERS = {
    "16GB": {
        "conservative": 16384,
        "balanced": 16384,
        "aggressive": 24576,
    },
    "24GB": {
        "conservative": 32768,
        "balanced": 49152,
        "aggressive": 65536,
    },
    "32GB": {
        "conservative": 65536,
        "balanced": 98304,
        "aggressive": 131072,
    },
    "48GB": {
        "conservative": 98304,
        "balanced": 131072,
        "aggressive": 131072,
    },
    "64GB+": {
        "conservative": 131072,
        "balanced": 131072,
        "aggressive": 131072,
    },
}

# Context fallback chain (largest to smallest)
CONTEXT_FALLBACK_CHAIN = [131072, 98304, 65536, 49152, 32768, 24576, 16384]

# Launch Agent configuration
LAUNCH_AGENT_LABEL = "com.llamacpp.server"
LAUNCH_AGENT_PLIST = f"{LAUNCH_AGENT_LABEL}.plist"
LAUNCH_AGENTS_DIR = Path.home() / "Library" / "LaunchAgents"

# VPN-resilient environment variables
VPN_RESILIENT_ENV = {
    "NO_PROXY": "localhost,127.0.0.1,::1",
}


@dataclass
class ServerConfig:
    """Llama.cpp server configuration."""
    host: str = DEFAULT_HOST
    port: int = DEFAULT_PORT
    model_path: Optional[Path] = None
    context_size: int = 16384
    n_gpu_layers: int = -1
    parallel: int = 2
    cont_batching: bool = True
    metrics: bool = True
    log_format: str = "json"
    flash_attn: bool = True
    no_mmap: bool = True
    rope_scaling: Optional[str] = None
    yarn_ext_factor: Optional[float] = None
    binary_path: Optional[Path] = None


def setup_vpn_resilient_environment() -> None:
    """Configure environment for VPN resilience."""
    for key, value in VPN_RESILIENT_ENV.items():
        os.environ[key] = value


def get_api_base() -> str:
    """Get API base URL."""
    host = os.environ.get("LLAMACPP_HOST", DEFAULT_HOST)
    port = int(os.environ.get("LLAMACPP_PORT", DEFAULT_PORT))
    return f"http://{host}:{port}"


def get_binary_path() -> Path:
    """Get path to llama.cpp server binary."""
    return LLAMACPP_BIN_DIR / "llama-server"


def get_latest_release_url() -> Tuple[bool, str]:
    """
    Get latest llama.cpp release URL for macOS Apple Silicon.
    
    Returns:
        Tuple of (success, url_or_error)
    """
    try:
        api_url = "https://api.github.com/repos/ggerganov/llama.cpp/releases/latest"
        req = urllib.request.Request(api_url)
        req.add_header("Accept", "application/vnd.github.v3+json")
        
        with urllib.request.urlopen(req, timeout=10, context=utils.get_unverified_ssl_context()) as response:
            if response.status == 200:
                data = json.loads(response.read().decode('utf-8'))
                assets = data.get("assets", [])
                
                for asset in assets:
                    name = asset.get("name", "")
                    if "server" in name.lower() and "darwin" in name.lower() and "arm64" in name.lower():
                        return True, asset.get("browser_download_url", "")
                
                return False, "No macOS ARM64 server binary found in latest release"
            else:
                return False, f"GitHub API returned status {response.status}"
    except Exception as e:
        return False, str(e)


def download_binary(url: str, dest_path: Path) -> Tuple[bool, str]:
    """
    Download llama.cpp server binary.
    
    Args:
        url: URL to download from
        dest_path: Destination path for binary
    
    Returns:
        Tuple of (success, message)
    """
    try:
        ui.print_info(f"Downloading llama.cpp server from {url}...")
        
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=300, context=utils.get_unverified_ssl_context()) as response:
            total_size = int(response.headers.get('Content-Length', 0))
            downloaded = 0
            
            dest_path.parent.mkdir(parents=True, exist_ok=True)
            
            with open(dest_path, 'wb') as f:
                while True:
                    chunk = response.read(8192)
                    if not chunk:
                        break
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total_size > 0:
                        percent = (downloaded / total_size) * 100
                        print(f"\r  Progress: {percent:.1f}%", end='', flush=True)
            
            print()  # New line after progress
            dest_path.chmod(0o755)
            ui.print_success(f"Binary downloaded to {dest_path}")
            return True, "Download successful"
    except Exception as e:
        return False, f"Download failed: {e}"


def install_binary() -> Tuple[bool, Path]:
    """
    Download and install llama.cpp server binary.
    
    Returns:
        Tuple of (success, binary_path)
    """
    binary_path = get_binary_path()
    
    if binary_path.exists():
        ui.print_info(f"Binary already exists at {binary_path}")
        return True, binary_path
    
    ui.print_subheader("Downloading llama.cpp Server Binary")
    
    success, url_or_error = get_latest_release_url()
    if not success:
        ui.print_error(f"Failed to get release URL: {url_or_error}")
        ui.print_info("You may need to build from source or download manually")
        return False, binary_path
    
    success, message = download_binary(url_or_error, binary_path)
    if not success:
        ui.print_error(message)
        return False, binary_path
    
    return True, binary_path


def get_model_download_url(quantization: str = DEFAULT_QUANTIZATION) -> Tuple[bool, str, str]:
    """
    Get model download URL for GPT-OSS 20B.
    
    Args:
        quantization: Model quantization (Q4_K_M, Q6_K_XL, Q8_K_XL)
    
    Returns:
        Tuple of (success, url, filename)
    """
    model_info = GPT_OSS_20B_MODELS.get(quantization)
    if not model_info:
        return False, "", f"Unknown quantization: {quantization}"
    
    filename = model_info["name"]
    # HuggingFace model URL pattern
    base_url = "https://huggingface.co/microsoft/gpt-oss-20b-gguf/resolve/main"
    url = f"{base_url}/{filename}"
    
    return True, url, filename


def download_model(quantization: str = DEFAULT_QUANTIZATION) -> Tuple[bool, Path]:
    """
    Download GPT-OSS 20B model.
    
    Args:
        quantization: Model quantization to download
    
    Returns:
        Tuple of (success, model_path)
    """
    model_path = LLAMACPP_MODEL_DIR / GPT_OSS_20B_MODELS[quantization]["name"]
    
    if model_path.exists():
        ui.print_info(f"Model already exists at {model_path}")
        return True, model_path
    
    ui.print_subheader(f"Downloading GPT-OSS 20B Model ({quantization})")
    
    success, url, filename = get_model_download_url(quantization)
    if not success:
        ui.print_error(f"Failed to get model URL: {url}")
        return False, model_path
    
    try:
        ui.print_info(f"Downloading {filename}...")
        ui.print_warning("This may take a while (model is ~12-18GB)")
        
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=3600, context=utils.get_unverified_ssl_context()) as response:
            total_size = int(response.headers.get('Content-Length', 0))
            downloaded = 0
            
            model_path.parent.mkdir(parents=True, exist_ok=True)
            
            with open(model_path, 'wb') as f:
                while True:
                    chunk = response.read(8192)
                    if not chunk:
                        break
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total_size > 0:
                        percent = (downloaded / total_size) * 100
                        mb_downloaded = downloaded / (1024 * 1024)
                        mb_total = total_size / (1024 * 1024)
                        print(f"\r  Progress: {percent:.1f}% ({mb_downloaded:.1f}MB / {mb_total:.1f}MB)", end='', flush=True)
            
            print()  # New line after progress
            ui.print_success(f"Model downloaded to {model_path}")
            return True, model_path
    except Exception as e:
        ui.print_error(f"Download failed: {e}")
        return False, model_path


def calculate_optimal_context_size(hw_info: hardware.HardwareInfo, quantization: str = DEFAULT_QUANTIZATION) -> Tuple[int, str]:
    """
    Calculate optimal context size based on RAM tier.
    
    Args:
        hw_info: Hardware information
        quantization: Model quantization
    
    Returns:
        Tuple of (context_size, reason)
    """
    ram_tier = hw_info.get_ram_tier()
    tier_config = CONTEXT_TIERS.get(ram_tier, CONTEXT_TIERS["16GB"])
    
    # Start with aggressive tier
    context_size = tier_config["aggressive"]
    reason = f"Starting with aggressive context size for {ram_tier} RAM tier"
    
    # Override from environment if set
    env_context = os.environ.get("LLAMACPP_CONTEXT_SIZE")
    if env_context:
        try:
            context_size = int(env_context)
            reason = f"Context size overridden from LLAMACPP_CONTEXT_SIZE={env_context}"
        except ValueError:
            pass
    
    return context_size, reason


def get_parallel_count(hw_info: hardware.HardwareInfo) -> int:
    """
    Get optimal parallel request count based on RAM.
    
    Args:
        hw_info: Hardware information
    
    Returns:
        Parallel request count
    """
    if hw_info.ram_gb >= 64:
        return 8
    elif hw_info.ram_gb >= 32:
        return 4
    else:
        return 2


def build_server_args(config: ServerConfig) -> List[str]:
    """
    Build command-line arguments for llama.cpp server.
    
    Args:
        config: Server configuration
    
    Returns:
        List of command-line arguments
    """
    args = [
        str(config.binary_path),
        "--host", config.host,
        "--port", str(config.port),
        "--model", str(config.model_path),
        "--ctx-size", str(config.context_size),
        "--n-gpu-layers", str(config.n_gpu_layers),
        "--parallel", str(config.parallel),
    ]
    
    if config.cont_batching:
        args.append("--cont-batching")
    
    if config.metrics:
        args.append("--metrics")
    
    if config.log_format:
        args.extend(["--log-format", config.log_format])
    
    if config.flash_attn:
        args.append("--flash-attn")
    
    if config.no_mmap:
        args.append("--no-mmap")
    
    if config.rope_scaling:
        args.extend(["--rope-scaling", config.rope_scaling])
        if config.yarn_ext_factor is not None:
            args.extend(["--yarn-ext-factor", str(config.yarn_ext_factor)])
    
    return args


def test_server_start(config: ServerConfig, timeout: int = 30) -> Tuple[bool, Optional[int]]:
    """
    Test if server can start with given configuration.
    
    Args:
        config: Server configuration
        timeout: Timeout in seconds
    
    Returns:
        Tuple of (success, actual_context_size_used)
    """
    if not config.binary_path or not config.binary_path.exists():
        return False, None
    
    if not config.model_path or not config.model_path.exists():
        return False, None
    
    args = build_server_args(config)
    
    try:
        process = subprocess.Popen(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={**os.environ, **VPN_RESILIENT_ENV}
        )
        
        # Wait for server to start or fail
        start_time = time.time()
        while time.time() - start_time < timeout:
            if process.poll() is not None:
                # Process exited
                stderr = process.stderr.read().decode('utf-8') if process.stderr else ""
                if "out of memory" in stderr.lower() or "oom" in stderr.lower():
                    return False, None
                return False, None
            
            # Check if server is responding
            try:
                req = urllib.request.Request(f"{get_api_base()}/health")
                with urllib.request.urlopen(req, timeout=2, context=utils.get_unverified_ssl_context()) as response:
                    if response.status == 200:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                        return True, config.context_size
            except (urllib.error.URLError, OSError):
                time.sleep(1)
        
        # Timeout - kill process
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
        
        return False, None
    except Exception as e:
        ui.print_warning(f"Test start failed: {e}")
        return False, None


def find_optimal_context_size(
    hw_info: hardware.HardwareInfo,
    model_path: Path,
    binary_path: Path,
    quantization: str = DEFAULT_QUANTIZATION
) -> Tuple[int, str]:
    """
    Find optimal context size with dynamic fallback.
    
    Args:
        hw_info: Hardware information
        model_path: Path to model file
        binary_path: Path to server binary
        quantization: Model quantization
    
    Returns:
        Tuple of (optimal_context_size, reason)
    """
    ui.print_subheader("Finding Optimal Context Size")
    
    # Start with recommended aggressive size
    initial_context, _ = calculate_optimal_context_size(hw_info, quantization)
    
    # Try context sizes from fallback chain, starting from initial
    test_contexts = []
    for ctx in CONTEXT_FALLBACK_CHAIN:
        if ctx <= initial_context:
            test_contexts.append(ctx)
    
    # Also try the initial context if not in chain
    if initial_context not in test_contexts:
        test_contexts.insert(0, initial_context)
    
    test_contexts = sorted(set(test_contexts), reverse=True)
    
    parallel = get_parallel_count(hw_info)
    
    for ctx_size in test_contexts:
        ui.print_info(f"Testing context size: {ctx_size:,} tokens...")
        
        config = ServerConfig(
            binary_path=binary_path,
            model_path=model_path,
            context_size=ctx_size,
            parallel=parallel,
            rope_scaling="yarn" if ctx_size > 32768 else None,
            yarn_ext_factor=1.0 if ctx_size > 32768 else None,
        )
        
        success, _ = test_server_start(config, timeout=45)
        if success:
            reason = f"Successfully tested context size {ctx_size:,} tokens"
            ui.print_success(reason)
            return ctx_size, reason
        
        ui.print_warning(f"Context size {ctx_size:,} failed, trying smaller...")
        time.sleep(2)  # Brief pause between tests
    
    # Fallback to minimum
    min_context = min(CONTEXT_FALLBACK_CHAIN)
    ui.print_warning(f"All context sizes failed, using minimum: {min_context:,}")
    return min_context, f"Using minimum context size {min_context:,} tokens"


def check_server_health() -> Tuple[bool, Optional[Dict]]:
    """
    Check if llama.cpp server is healthy.
    
    Returns:
        Tuple of (is_healthy, health_data)
    """
    try:
        req = urllib.request.Request(f"{get_api_base()}/health")
        with urllib.request.urlopen(req, timeout=5, context=utils.get_unverified_ssl_context()) as response:
            if response.status == 200:
                data = json.loads(response.read().decode('utf-8'))
                return True, data
            return False, None
    except Exception:
        return False, None


def get_server_status() -> Dict:
    """
    Get comprehensive server status.
    
    Returns:
        Dictionary with status information
    """
    is_healthy, health_data = check_server_health()
    
    status = {
        "running": is_healthy,
        "health": health_data,
    }
    
    # Check if process is running
    try:
        code, stdout, _ = utils.run_command(["pgrep", "-f", "llama-server"], timeout=2)
        status["process_running"] = code == 0
    except Exception:
        status["process_running"] = False
    
    # Try to get model info
    try:
        req = urllib.request.Request(f"{get_api_base()}/v1/models")
        with urllib.request.urlopen(req, timeout=5, context=utils.get_unverified_ssl_context()) as response:
            if response.status == 200:
                data = json.loads(response.read().decode('utf-8'))
                status["models"] = data.get("data", [])
    except Exception:
        status["models"] = []
    
    return status


def stop_server() -> bool:
    """
    Stop llama.cpp server.
    
    Returns:
        True if stopped successfully
    """
    try:
        # Find and kill process
        code, stdout, _ = utils.run_command(["pkill", "-f", "llama-server"], timeout=5)
        if code == 0:
            ui.print_success("Server stopped")
            return True
        
        # Check if it's actually stopped
        if not check_server_health()[0]:
            ui.print_success("Server is not running")
            return True
        
        ui.print_warning("Could not stop server process")
        return False
    except Exception as e:
        ui.print_error(f"Failed to stop server: {e}")
        return False


def create_launch_agent(config: ServerConfig) -> Tuple[bool, Path]:
    """
    Create macOS LaunchAgent for auto-start.
    
    Args:
        config: Server configuration
    
    Returns:
        Tuple of (success, plist_path)
    """
    plist_path = LAUNCH_AGENTS_DIR / LAUNCH_AGENT_PLIST
    
    # Build command
    args = build_server_args(config)
    program = str(config.binary_path)
    program_args = args[1:]  # Skip binary path
    
    # Create plist content
    plist_content = {
        "Label": LAUNCH_AGENT_LABEL,
        "ProgramArguments": [program] + program_args,
        "RunAtLoad": True,
        "KeepAlive": True,
        "StandardOutPath": str(LLAMACPP_LOG_DIR / "server.out.log"),
        "StandardErrorPath": str(LLAMACPP_LOG_DIR / "server.err.log"),
        "EnvironmentVariables": VPN_RESILIENT_ENV,
    }
    
    try:
        LAUNCH_AGENTS_DIR.mkdir(parents=True, exist_ok=True)
        LLAMACPP_LOG_DIR.mkdir(parents=True, exist_ok=True)
        
        with open(plist_path, 'wb') as f:
            plistlib.dump(plist_content, f)
        
        ui.print_success(f"LaunchAgent created at {plist_path}")
        return True, plist_path
    except Exception as e:
        ui.print_error(f"Failed to create LaunchAgent: {e}")
        return False, plist_path


def load_launch_agent(plist_path: Path) -> bool:
    """
    Load LaunchAgent.
    
    Args:
        plist_path: Path to plist file
    
    Returns:
        True if loaded successfully
    """
    try:
        code, stdout, stderr = utils.run_command(
            ["launchctl", "load", str(plist_path)],
            timeout=10
        )
        if code == 0:
            ui.print_success("LaunchAgent loaded")
            return True
        else:
            ui.print_warning(f"Could not load LaunchAgent: {stderr}")
            return False
    except Exception as e:
        ui.print_error(f"Failed to load LaunchAgent: {e}")
        return False


def unload_launch_agent() -> bool:
    """
    Unload LaunchAgent.
    
    Returns:
        True if unloaded successfully
    """
    try:
        code, stdout, stderr = utils.run_command(
            ["launchctl", "unload", str(LAUNCH_AGENTS_DIR / LAUNCH_AGENT_PLIST)],
            timeout=10
        )
        if code == 0:
            ui.print_success("LaunchAgent unloaded")
            return True
        return False
    except Exception:
        return False


def benchmark_server(num_requests: int = 10) -> Dict:
    """
    Run performance benchmark on server.
    
    Args:
        num_requests: Number of requests to send
    
    Returns:
        Dictionary with benchmark results
    """
    ui.print_subheader("Running Performance Benchmark")
    
    if not check_server_health()[0]:
        ui.print_error("Server is not running")
        return {"error": "Server not running"}
    
    import time
    
    results = {
        "num_requests": num_requests,
        "total_time": 0.0,
        "tokens_per_second": 0.0,
        "requests_per_second": 0.0,
    }
    
    test_prompt = "The quick brown fox jumps over the lazy dog. " * 10
    
    start_time = time.time()
    successful_requests = 0
    total_tokens = 0
    
    for i in range(num_requests):
        try:
            req_data = {
                "model": "gpt-oss-20b",
                "messages": [{"role": "user", "content": test_prompt}],
                "max_tokens": 100,
            }
            
            req = urllib.request.Request(
                f"{get_api_base()}/v1/chat/completions",
                data=json.dumps(req_data).encode('utf-8'),
                headers={"Content-Type": "application/json"}
            )
            
            request_start = time.time()
            with urllib.request.urlopen(req, timeout=30, context=utils.get_unverified_ssl_context()) as response:
                if response.status == 200:
                    data = json.loads(response.read().decode('utf-8'))
                    usage = data.get("usage", {})
                    total_tokens += usage.get("total_tokens", 0)
                    successful_requests += 1
        except Exception as e:
            ui.print_warning(f"Request {i+1} failed: {e}")
    
    total_time = time.time() - start_time
    
    if successful_requests > 0:
        results["total_time"] = total_time
        results["tokens_per_second"] = total_tokens / total_time if total_time > 0 else 0
        results["requests_per_second"] = successful_requests / total_time if total_time > 0 else 0
        results["successful_requests"] = successful_requests
        
        ui.print_success(f"Benchmark complete: {results['tokens_per_second']:.1f} tokens/sec")
    else:
        results["error"] = "All requests failed"
        ui.print_error("Benchmark failed")
    
    return results


def get_server_logs(lines: int = 50) -> List[str]:
    """
    Get server logs.
    
    Args:
        lines: Number of lines to retrieve
    
    Returns:
        List of log lines
    """
    log_file = LLAMACPP_LOG_DIR / "server.out.log"
    error_log = LLAMACPP_LOG_DIR / "server.err.log"
    
    logs = []
    
    if error_log.exists():
        try:
            with open(error_log, 'r', encoding='utf-8') as f:
                error_lines = f.readlines()
                logs.extend([f"[ERROR] {line.rstrip()}" for line in error_lines[-lines:]])
        except Exception:
            pass
    
    if log_file.exists():
        try:
            with open(log_file, 'r', encoding='utf-8') as f:
                log_lines = f.readlines()
                logs.extend([f"[INFO] {line.rstrip()}" for line in log_lines[-lines:]])
        except Exception:
            pass
    
    return logs[-lines:] if logs else []


def optimize_context(
    hw_info: hardware.HardwareInfo,
    model_path: Path,
    binary_path: Path,
    quantization: str = DEFAULT_QUANTIZATION
) -> int:
    """
    Test progressively larger contexts to find maximum stable size.
    
    Args:
        hw_info: Hardware information
        model_path: Path to model file
        binary_path: Path to server binary
        quantization: Model quantization
    
    Returns:
        Largest stable context size
    """
    ui.print_subheader("Optimizing Context Size")
    
    initial_context, _ = calculate_optimal_context_size(hw_info, quantization)
    parallel = get_parallel_count(hw_info)
    
    # Start from initial and increase by 8K increments
    test_sizes = [initial_context]
    current = initial_context
    
    while current < 131072:  # Max context
        current += 8192
        test_sizes.append(current)
    
    max_stable = initial_context
    
    for ctx_size in test_sizes:
        ui.print_info(f"Testing context size: {ctx_size:,} tokens...")
        
        config = ServerConfig(
            binary_path=binary_path,
            model_path=model_path,
            context_size=ctx_size,
            parallel=parallel,
            rope_scaling="yarn" if ctx_size > 32768 else None,
            yarn_ext_factor=1.0 if ctx_size > 32768 else None,
        )
        
        success, _ = test_server_start(config, timeout=45)
        if success:
            max_stable = ctx_size
            ui.print_success(f"Context size {ctx_size:,} tokens is stable")
        else:
            ui.print_warning(f"Context size {ctx_size:,} failed")
            break
        
        time.sleep(2)
    
    ui.print_success(f"Maximum stable context size: {max_stable:,} tokens")
    
    # Save result
    cache_file = LLAMACPP_CACHE_DIR / "optimal_context.txt"
    try:
        cache_file.parent.mkdir(parents=True, exist_ok=True)
        with open(cache_file, 'w') as f:
            f.write(str(max_stable))
    except Exception:
        pass
    
    return max_stable


def upgrade_binary() -> Tuple[bool, str]:
    """
    Upgrade llama.cpp server binary to latest version.
    
    Returns:
        Tuple of (success, message)
    """
    ui.print_subheader("Upgrading llama.cpp Server Binary")
    
    binary_path = get_binary_path()
    
    # Backup old binary
    if binary_path.exists():
        backup_path = binary_path.with_suffix('.backup')
        try:
            shutil.copy2(binary_path, backup_path)
            ui.print_info("Backed up existing binary")
        except Exception:
            pass
    
    # Download new binary
    success, url_or_error = get_latest_release_url()
    if not success:
        return False, f"Failed to get release URL: {url_or_error}"
    
    success, message = download_binary(url_or_error, binary_path)
    if not success:
        # Restore backup if download failed
        if binary_path.exists() and backup_path.exists():
            try:
                shutil.copy2(backup_path, binary_path)
            except Exception:
                pass
        return False, message
    
    ui.print_success("Binary upgraded successfully")
    return True, "Upgrade successful"
