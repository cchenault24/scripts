#!/usr/bin/env python3
"""
Llama.cpp Server Setup Script for macOS Apple Silicon

Deploys and manages llama.cpp server for macOS Apple Silicon (M1-M5) with GPT-OSS 20B model.

This script is macOS-only and requires Apple Silicon.

Features:
- Automatic binary download and installation (or build from source)
- Model download with verification
- Dynamic context sizing with fallback
- VPN-resilient configuration (127.0.0.1)
- LaunchAgent for auto-start
- Health checks and monitoring
- Comprehensive error handling

Requirements:
- Python 3.8+
- macOS with Apple Silicon (M1-M5)
- 16GB+ RAM (24GB+ recommended for GPT-OSS 20B)

Author: AI-Generated for Local LLM Development
License: MIT
"""

from __future__ import annotations

import argparse
import logging
import platform
import sys
from pathlib import Path
from typing import Tuple

# Add llamacpp directory to path
script_path = Path(__file__).resolve() if __file__ else Path(sys.argv[0]).resolve()
llamacpp_dir = script_path.parent
llamacpp_dir_str = str(llamacpp_dir)
if llamacpp_dir_str not in sys.path:
    sys.path.insert(0, llamacpp_dir_str)

from lib import hardware
from lib import llamacpp
from lib import ui
from lib import utils

# Configure VPN resilience at startup
llamacpp.setup_vpn_resilient_environment()

_logger = logging.getLogger(__name__)


def check_system_requirements() -> Tuple[bool, str]:
    """
    Check if system meets requirements (macOS only).
    
    Returns:
        Tuple of (meets_requirements, message)
    """
    if platform.system() != "Darwin":
        return False, "This script requires macOS (Apple Silicon)"
    
    hw_info = hardware.detect_hardware()
    
    if not hw_info.has_apple_silicon:
        return False, "This script requires Apple Silicon (M1-M5)"
    
    if hw_info.ram_gb < 16:
        return False, f"Insufficient RAM: {hw_info.ram_gb:.1f}GB (minimum 16GB required)"
    
    return True, "System requirements met"


def install() -> int:
    """Main installation function."""
    try:
        ui.init_logging()
    except Exception:
        pass
    
    ui.clear_screen()
    ui.print_header("🚀 Llama.cpp Server Setup for Enterprise")
    ui.print_info("GPT-OSS 20B Model Configuration")
    print()
    
    if not ui.prompt_yes_no("Ready to begin setup?", default=True):
        ui.print_info("Setup cancelled. Run again when ready!")
        return 0
    
    # Check system requirements and detect hardware
    print()
    ui.print_subheader("System Check")
    meets_requirements, message = check_system_requirements()
    if not meets_requirements:
        ui.print_error(message)
        return 1
    
    hw_info = hardware.detect_hardware()
    ui.print_success("System requirements met")
    
    # Check if server is already running
    is_healthy, _ = llamacpp.check_server_health()
    if is_healthy:
        ui.print_warning("Server is already running on port 8080")
    
    # Install binary (automatically builds from source if needed)
    print()
    ui.print_subheader("Installing Server Binary")
    binary_success, binary_path = llamacpp.install_binary()
    if not binary_success:
        ui.print_error("Failed to install binary")
        return 1
    
    # Select quantization (default to Q4_K_M for best compatibility)
    print()
    ui.print_subheader("Downloading Model")
    quantization = "Q4_K_M"  # Default to recommended quantization
    ui.print_info(f"Using quantization: {quantization} (12GB, recommended)")
    
    # Download model
    print()
    model_success, model_path = llamacpp.download_model(quantization)
    if not model_success:
        ui.print_error("Failed to download model")
        return 1
    
    # Find optimal context size
    print()
    optimal_context, context_reason = llamacpp.find_optimal_context_size(
        hw_info, model_path, binary_path, quantization
    )
    ui.print_success(f"Optimal context size: {optimal_context:,} tokens")
    ui.print_info(context_reason)
    
    # Get configuration
    port = int(os.environ.get("LLAMACPP_PORT", llamacpp.DEFAULT_PORT))
    host = os.environ.get("LLAMACPP_HOST", llamacpp.DEFAULT_HOST)
    parallel = llamacpp.get_parallel_count(hw_info)
    
    # Build server configuration
    config = llamacpp.ServerConfig(
        host=host,
        port=port,
        model_path=model_path,
        context_size=optimal_context,
        binary_path=binary_path,
        parallel=parallel,
        rope_scaling="yarn" if optimal_context > 32768 else None,
        yarn_ext_factor=1.0 if optimal_context > 32768 else None,
    )
    
    # Test server startup
    print()
    ui.print_subheader("Testing Server Startup")
    test_success, _ = llamacpp.test_server_start(config, timeout=60)
    if not test_success:
        ui.print_error("Server failed to start with optimal configuration")
        ui.print_info("Trying with reduced context size...")
        
        # Try with smaller context
        config.context_size = min(optimal_context, 16384)
        test_success, _ = llamacpp.test_server_start(config, timeout=60)
        if not test_success:
            ui.print_error("Server failed to start even with reduced context")
            return 1
    
    ui.print_success("Server test successful")
    
    # Create LaunchAgent for auto-start
    print()
    ui.print_subheader("Configuring Auto-Start")
    agent_success, plist_path = llamacpp.create_launch_agent(config)
    if agent_success:
        llamacpp.load_launch_agent(plist_path)
        ui.print_success("Auto-start configured")
    
    # Verify installation
    print()
    ui.print_subheader("Verifying Installation")
    
    # Wait a bit for server to be ready
    import time
    time.sleep(3)
    
    is_healthy, health_data = llamacpp.check_server_health()
    if is_healthy:
        ui.print_success("Server is running and healthy")
        
        # Get model info
        try:
            status = llamacpp.get_server_status()
            models = status.get("models", [])
            if models:
                ui.print_info(f"Model: {models[0].get('id', 'unknown')}")
        except Exception:
            pass
        
        ui.print_info(f"Web UI: http://{host}:{port}/")
        ui.print_info(f"API: http://{host}:{port}/v1")
        ui.print_info(f"Health: http://{host}:{port}/health")
        ui.print_info(f"Context size: {optimal_context:,} tokens")
    else:
        ui.print_warning("Server health check failed")
        ui.print_info("You may need to start the server manually")
    
    print()
    ui.print_success("Setup complete!")
    return 0


def status() -> int:
    """Show server status."""
    ui.print_subheader("Server Status")
    
    status_data = llamacpp.get_server_status()
    
    if status_data.get("running"):
        ui.print_success("Server is running")
        
        health = status_data.get("health", {})
        if health:
            ui.print_info(f"Status: {health.get('status', 'unknown')}")
        
        models = status_data.get("models", [])
        if models:
            for model in models:
                ui.print_info(f"Model: {model.get('id', 'unknown')}")
        
        api_base = llamacpp.get_api_base()
        ui.print_info(f"API: {api_base}")
    else:
        ui.print_error("Server is not running")
        
        if status_data.get("process_running"):
            ui.print_warning("Process is running but API is not responding")
        else:
            ui.print_info("No server process found")
    
    return 0


def stop() -> int:
    """Stop server."""
    ui.print_subheader("Stopping Server")
    
    # Unload LaunchAgent first
    llamacpp.unload_launch_agent()
    
    # Stop server
    success = llamacpp.stop_server()
    return 0 if success else 1


def restart() -> int:
    """Restart server."""
    ui.print_subheader("Restarting Server")
    
    # Stop first
    llamacpp.stop_server()
    llamacpp.unload_launch_agent()
    
    # Reload LaunchAgent
    plist_path = llamacpp.LAUNCH_AGENTS_DIR / llamacpp.LAUNCH_AGENT_PLIST
    if plist_path.exists():
        llamacpp.load_launch_agent(plist_path)
        ui.print_success("Server restarted")
    else:
        ui.print_error("LaunchAgent not found. Run setup first.")
        return 1
    
    return 0


def uninstall() -> int:
    """Uninstall server."""
    ui.print_subheader("Uninstalling llama.cpp Server")
    
    if not ui.prompt_yes_no("Are you sure you want to uninstall?", default=False):
        ui.print_info("Uninstall cancelled")
        return 0
    
    # Stop server
    llamacpp.stop_server()
    llamacpp.unload_launch_agent()
    
    # Remove LaunchAgent
    plist_path = llamacpp.LAUNCH_AGENTS_DIR / llamacpp.LAUNCH_AGENT_PLIST
    if plist_path.exists():
        try:
            plist_path.unlink()
            ui.print_success("LaunchAgent removed")
        except Exception as e:
            ui.print_warning(f"Could not remove LaunchAgent: {e}")
    
    # Optionally remove binary and model
    if ui.prompt_yes_no("Remove binary and model files?", default=False):
        binary_path = llamacpp.get_binary_path()
        if binary_path.exists():
            try:
                binary_path.unlink()
                ui.print_success("Binary removed")
            except Exception as e:
                ui.print_warning(f"Could not remove binary: {e}")
        
        model_path = llamacpp.LLAMACPP_MODEL_DIR / llamacpp.DEFAULT_MODEL
        if model_path.exists():
            try:
                model_path.unlink()
                ui.print_success("Model removed")
            except Exception as e:
                ui.print_warning(f"Could not remove model: {e}")
    
    ui.print_success("Uninstall complete")
    return 0


def upgrade() -> int:
    """Upgrade binary."""
    ui.print_subheader("Upgrading llama.cpp Server Binary")
    
    success, message = llamacpp.upgrade_binary()
    if success:
        ui.print_success(message)
        return 0
    else:
        ui.print_error(message)
        return 1


def benchmark() -> int:
    """Run benchmark."""
    results = llamacpp.benchmark_server()
    
    if "error" in results:
        return 1
    
    ui.print_info(f"Tokens/sec: {results['tokens_per_second']:.1f}")
    ui.print_info(f"Requests/sec: {results['requests_per_second']:.2f}")
    
    return 0


def logs() -> int:
    """Show logs."""
    ui.print_subheader("Server Logs")
    
    log_lines = llamacpp.get_server_logs(100)
    if log_lines:
        for line in log_lines:
            print(line)
    else:
        ui.print_info("No logs available")
    
    return 0


def optimize_context() -> int:
    """Optimize context size."""
    hw_info = hardware.detect_hardware()
    
    binary_path = llamacpp.get_binary_path()
    if not binary_path.exists():
        ui.print_error("Binary not found. Run setup first.")
        return 1
    
    # Find model
    model_path = None
    for quant in ["Q4_K_M", "Q6_K_XL", "Q8_K_XL"]:
        model_name = llamacpp.GPT_OSS_20B_MODELS[quant]["name"]
        test_path = llamacpp.LLAMACPP_MODEL_DIR / model_name
        if test_path.exists():
            model_path = test_path
            break
    
    if not model_path:
        ui.print_error("Model not found. Run setup first.")
        return 1
    
    optimal = llamacpp.optimize_context(hw_info, model_path, binary_path)
    ui.print_success(f"Optimal context size: {optimal:,} tokens")
    
    return 0


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Llama.cpp Server Setup and Management",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    subparsers = parser.add_subparsers(dest="command", help="Command to run")
    
    subparsers.add_parser("install", help="Install llama.cpp server")
    subparsers.add_parser("status", help="Show server status")
    subparsers.add_parser("stop", help="Stop server")
    subparsers.add_parser("restart", help="Restart server")
    subparsers.add_parser("uninstall", help="Uninstall server")
    subparsers.add_parser("upgrade", help="Upgrade binary")
    subparsers.add_parser("benchmark", help="Run performance benchmark")
    subparsers.add_parser("logs", help="Show server logs")
    subparsers.add_parser("optimize-context", help="Find optimal context size")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 0
    
    command_map = {
        "install": install,
        "status": status,
        "stop": stop,
        "restart": restart,
        "uninstall": uninstall,
        "upgrade": upgrade,
        "benchmark": benchmark,
        "logs": logs,
        "optimize-context": optimize_context,
    }
    
    handler = command_map.get(args.command)
    if not handler:
        parser.print_help()
        return 1
    
    try:
        return handler()
    except KeyboardInterrupt:
        print()
        ui.print_warning("Operation interrupted by user.")
        return 130
    except Exception as e:
        ui.print_error(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
