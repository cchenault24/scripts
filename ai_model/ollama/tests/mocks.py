"""
Reusable mock objects and helper functions for testing.

Provides mock classes that can be configured for different test scenarios.
"""

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple
from unittest.mock import MagicMock, Mock


# =============================================================================
# Mock Hardware
# =============================================================================

@dataclass
class MockHardwareInfo:
    """
    Configurable hardware mock for testing different system configurations.
    
    Example:
        hw = MockHardwareInfo(ram_gb=16.0, has_apple_silicon=True)
        assert hw.tier == "Tier C"
    """
    ram_gb: float = 16.0
    cpu_cores: int = 8
    cpu_brand: str = "Apple M4"
    has_apple_silicon: bool = True
    has_nvidia: bool = False
    gpu_name: str = "Apple M4"
    ollama_available: bool = True
    ollama_version: str = "0.13.5"
    
    @property
    def tier(self) -> str:
        """Calculate tier based on RAM."""
        if self.ram_gb >= 64:
            return "Tier S"
        elif self.ram_gb >= 32:
            return "Tier A"
        elif self.ram_gb >= 24:
            return "Tier B"
        else:
            return "Tier C"
    
    @property
    def tier_enum(self):
        """Get HardwareTier enum value."""
        from lib.hardware import HardwareTier
        if self.ram_gb >= 64:
            return HardwareTier.S
        elif self.ram_gb >= 32:
            return HardwareTier.A
        elif self.ram_gb >= 24:
            return HardwareTier.B
        else:
            return HardwareTier.C
    
    @property
    def usable_ram_gb(self) -> float:
        """Calculate usable RAM based on tier reservation."""
        if self.ram_gb >= 32:
            return self.ram_gb * 0.70  # 30% reservation
        elif self.ram_gb >= 24:
            return self.ram_gb * 0.65  # 35% reservation
        else:
            return self.ram_gb * 0.60  # 40% reservation


# =============================================================================
# Mock Ollama API
# =============================================================================

class MockOllamaAPI:
    """
    Mock Ollama API responses for testing.
    
    Example:
        api = MockOllamaAPI()
        api.set_installed_models(["qwen2.5-coder:7b", "nomic-embed-text"])
        response = api.get_tags()
    """
    
    def __init__(self):
        self.installed_models: List[Dict[str, Any]] = []
        self.is_running: bool = True
        self.pull_failures: Dict[str, str] = {}  # model_name -> error_message
        self.active_models: List[str] = []
    
    def set_installed_models(self, models: List[str]) -> None:
        """Set the list of installed models."""
        self.installed_models = [
            {
                "name": model,
                "size": 5000000000,
                "digest": f"sha256:mock_{model}",
                "modified_at": "2024-01-01T00:00:00Z"
            }
            for model in models
        ]
    
    def add_pull_failure(self, model: str, error: str) -> None:
        """Configure a model to fail when pulled."""
        self.pull_failures[model] = error
    
    def get_tags(self) -> Dict[str, Any]:
        """Mock /api/tags response."""
        if not self.is_running:
            raise ConnectionRefusedError("Ollama not running")
        return {"models": self.installed_models}
    
    def get_ps(self) -> Dict[str, Any]:
        """Mock /api/ps response (running models)."""
        if not self.is_running:
            raise ConnectionRefusedError("Ollama not running")
        return {
            "models": [{"name": m} for m in self.active_models]
        }
    
    def pull_model(self, model_name: str) -> Tuple[bool, str]:
        """Mock model pull operation."""
        if not self.is_running:
            return False, "Ollama not running"
        
        if model_name in self.pull_failures:
            return False, self.pull_failures[model_name]
        
        # Add to installed models
        self.installed_models.append({
            "name": model_name,
            "size": 5000000000,
            "digest": f"sha256:mock_{model_name}",
            "modified_at": "2024-01-01T00:00:00Z"
        })
        return True, ""
    
    def create_mock_response(self, data: Dict[str, Any], status: int = 200) -> MagicMock:
        """Create a mock urllib response."""
        mock_response = MagicMock()
        mock_response.status = status
        mock_response.read.return_value = json.dumps(data).encode()
        mock_response.__enter__ = Mock(return_value=mock_response)
        mock_response.__exit__ = Mock(return_value=False)
        return mock_response


# =============================================================================
# Mock File System
# =============================================================================

class MockFileSystem:
    """
    Mock file system operations for testing.
    
    Example:
        fs = MockFileSystem(base_path="/tmp/test")
        fs.create_file("config.yaml", "content: test")
        assert fs.file_exists("config.yaml")
    """
    
    def __init__(self, base_path: Optional[Path] = None):
        self.base_path = Path(base_path) if base_path else Path("/tmp/mock_fs")
        self.files: Dict[str, str] = {}
        self.directories: set = set()
        self.write_errors: Dict[str, Exception] = {}
        self.read_errors: Dict[str, Exception] = {}
    
    def create_file(self, path: str, content: str = "") -> None:
        """Create a mock file."""
        self.files[path] = content
    
    def create_directory(self, path: str) -> None:
        """Create a mock directory."""
        self.directories.add(path)
    
    def file_exists(self, path: str) -> bool:
        """Check if mock file exists."""
        return path in self.files
    
    def directory_exists(self, path: str) -> bool:
        """Check if mock directory exists."""
        return path in self.directories
    
    def read_file(self, path: str) -> str:
        """Read mock file content."""
        if path in self.read_errors:
            raise self.read_errors[path]
        if path not in self.files:
            raise FileNotFoundError(f"No such file: {path}")
        return self.files[path]
    
    def write_file(self, path: str, content: str) -> None:
        """Write to mock file."""
        if path in self.write_errors:
            raise self.write_errors[path]
        self.files[path] = content
    
    def delete_file(self, path: str) -> None:
        """Delete mock file."""
        if path in self.files:
            del self.files[path]
    
    def set_write_error(self, path: str, error: Exception) -> None:
        """Configure a path to raise an error on write."""
        self.write_errors[path] = error
    
    def set_read_error(self, path: str, error: Exception) -> None:
        """Configure a path to raise an error on read."""
        self.read_errors[path] = error


# =============================================================================
# Mock Subprocess
# =============================================================================

class MockSubprocess:
    """
    Mock subprocess operations for testing.
    
    Example:
        sp = MockSubprocess()
        sp.set_command_result("ollama list", 0, "models...", "")
        code, stdout, stderr = sp.run_command(["ollama", "list"])
    """
    
    def __init__(self):
        self.command_results: Dict[str, Tuple[int, str, str]] = {}
        self.command_history: List[List[str]] = []
        self.default_success: bool = True
    
    def set_command_result(
        self,
        command_pattern: str,
        returncode: int,
        stdout: str = "",
        stderr: str = ""
    ) -> None:
        """Set the result for a command pattern."""
        self.command_results[command_pattern] = (returncode, stdout, stderr)
    
    def run_command(
        self,
        cmd: List[str],
        timeout: int = 300
    ) -> Tuple[int, str, str]:
        """Mock command execution."""
        self.command_history.append(cmd)
        cmd_str = " ".join(cmd)
        
        # Check for matching pattern
        for pattern, result in self.command_results.items():
            if pattern in cmd_str:
                return result
        
        # Default behavior
        if self.default_success:
            return 0, "", ""
        else:
            return 1, "", "Command failed"
    
    def get_command_history(self) -> List[List[str]]:
        """Get history of executed commands."""
        return self.command_history
    
    def clear_history(self) -> None:
        """Clear command history."""
        self.command_history = []


# =============================================================================
# Mock Network
# =============================================================================

class MockNetwork:
    """
    Mock network operations for testing.
    
    Example:
        network = MockNetwork()
        network.set_url_response("https://ollama.com", 200, "OK")
        response = network.request("https://ollama.com")
    """
    
    def __init__(self):
        self.url_responses: Dict[str, Tuple[int, str]] = {}
        self.url_errors: Dict[str, Exception] = {}
        self.request_history: List[str] = []
        self.default_timeout_error: bool = False
    
    def set_url_response(self, url: str, status: int, content: str) -> None:
        """Set response for a URL."""
        self.url_responses[url] = (status, content)
    
    def set_url_error(self, url: str, error: Exception) -> None:
        """Configure a URL to raise an error."""
        self.url_errors[url] = error
    
    def request(self, url: str, timeout: int = 10) -> Tuple[int, str]:
        """Mock network request."""
        self.request_history.append(url)
        
        if self.default_timeout_error:
            import socket
            raise socket.timeout("Connection timed out")
        
        if url in self.url_errors:
            raise self.url_errors[url]
        
        for pattern, response in self.url_responses.items():
            if pattern in url:
                return response
        
        return 200, ""
    
    def create_mock_urlopen(self) -> Callable:
        """Create a mock urlopen function."""
        def mock_urlopen(request, timeout=None, context=None):
            url = request.full_url if hasattr(request, 'full_url') else str(request)
            self.request_history.append(url)
            
            if url in self.url_errors:
                raise self.url_errors[url]
            
            for pattern, (status, content) in self.url_responses.items():
                if pattern in url:
                    mock_response = MagicMock()
                    mock_response.status = status
                    mock_response.read.return_value = content.encode()
                    mock_response.__enter__ = Mock(return_value=mock_response)
                    mock_response.__exit__ = Mock(return_value=False)
                    return mock_response
            
            # Default successful response
            mock_response = MagicMock()
            mock_response.status = 200
            mock_response.read.return_value = b'{"models": []}'
            mock_response.__enter__ = Mock(return_value=mock_response)
            mock_response.__exit__ = Mock(return_value=False)
            return mock_response
        
        return mock_urlopen


# =============================================================================
# Mock User Interface
# =============================================================================

class MockUI:
    """
    Mock UI operations for testing without console output.
    
    Example:
        ui = MockUI()
        ui.set_prompt_responses(["y", "n", "1"])
        response = ui.prompt_yes_no("Continue?")
    """
    
    def __init__(self):
        self.prompt_responses: List[str] = []
        self.prompt_index: int = 0
        self.printed_messages: List[str] = []
        self.printed_errors: List[str] = []
        self.printed_warnings: List[str] = []
    
    def set_prompt_responses(self, responses: List[str]) -> None:
        """Set responses for prompts."""
        self.prompt_responses = responses
        self.prompt_index = 0
    
    def get_next_response(self) -> str:
        """Get next prompt response."""
        if self.prompt_index < len(self.prompt_responses):
            response = self.prompt_responses[self.prompt_index]
            self.prompt_index += 1
            return response
        return ""
    
    def print_info(self, message: str) -> None:
        """Mock print_info."""
        self.printed_messages.append(message)
    
    def print_error(self, message: str) -> None:
        """Mock print_error."""
        self.printed_errors.append(message)
    
    def print_warning(self, message: str) -> None:
        """Mock print_warning."""
        self.printed_warnings.append(message)
    
    def prompt_yes_no(self, question: str, default: bool = True) -> bool:
        """Mock yes/no prompt."""
        response = self.get_next_response().lower()
        if response == "y":
            return True
        elif response == "n":
            return False
        return default
    
    def prompt_choice(self, question: str, choices: List[str], default: int = 0) -> int:
        """Mock choice prompt."""
        response = self.get_next_response()
        try:
            return int(response)
        except ValueError:
            return default


# =============================================================================
# Helper Functions
# =============================================================================

def create_mock_popen(
    returncode: int = 0,
    stdout: str = "",
    stderr: str = ""
) -> MagicMock:
    """Create a mock Popen object."""
    mock_popen = MagicMock()
    mock_popen.returncode = returncode
    mock_popen.stdout = MagicMock()
    mock_popen.stdout.__iter__ = Mock(return_value=iter(stdout.split("\n")))
    mock_popen.stderr = MagicMock()
    mock_popen.stderr.read.return_value = stderr
    mock_popen.poll.return_value = returncode
    mock_popen.wait.return_value = returncode
    mock_popen.communicate.return_value = (stdout, stderr)
    return mock_popen


def create_mock_path(
    exists: bool = True,
    is_file: bool = True,
    content: str = ""
) -> MagicMock:
    """Create a mock Path object."""
    mock_path = MagicMock(spec=Path)
    mock_path.exists.return_value = exists
    mock_path.is_file.return_value = is_file
    mock_path.is_dir.return_value = not is_file
    mock_path.read_text.return_value = content
    mock_path.name = "mock_file"
    mock_path.suffix = ".txt"
    return mock_path


def assert_ssl_context_used(mock_urlopen: MagicMock) -> None:
    """Assert that SSL context was passed to urlopen."""
    for call in mock_urlopen.call_args_list:
        args, kwargs = call
        assert "context" in kwargs, "SSL context not passed to urlopen"
        assert kwargs["context"] is not None, "SSL context is None"


def assert_command_contains(
    mock_subprocess: MockSubprocess,
    expected_parts: List[str]
) -> None:
    """Assert that a command was executed with expected parts."""
    for cmd in mock_subprocess.command_history:
        cmd_str = " ".join(cmd)
        if all(part in cmd_str for part in expected_parts):
            return
    
    raise AssertionError(
        f"No command found containing all parts: {expected_parts}\n"
        f"Commands executed: {mock_subprocess.command_history}"
    )
