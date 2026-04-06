"""Unit tests for lib/prerequisites.py"""

from pathlib import Path
from unittest.mock import MagicMock, patch
import pytest

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from lib import prerequisites
from lib.prerequisites import Prerequisite, InstallMethod


class TestPrerequisiteDetection:
    """Test tool detection logic."""

    def test_is_tool_available_in_path(self):
        """Test detecting tool in PATH."""
        prereq = Prerequisite("git", InstallMethod.HOMEBREW, "git", [Path("/usr/bin/git")])

        with patch('shutil.which', return_value="/usr/bin/git"):
            assert prerequisites.is_tool_available(prereq) is True

    def test_is_tool_available_not_found(self):
        """Test tool not found."""
        prereq = Prerequisite("fake-tool", InstallMethod.HOMEBREW, "fake", [Path("/fake/path")])

        with patch('shutil.which', return_value=None):
            assert prerequisites.is_tool_available(prereq) is False

    def test_is_tool_available_in_known_location(self):
        """Test detecting tool in known location."""
        with patch('shutil.which', return_value=None):
            prereq = Prerequisite("test", InstallMethod.HOMEBREW, "test", [Path("/usr/local/bin/test")])

            with patch.object(Path, 'exists', return_value=True):
                with patch.object(Path, 'is_file', return_value=True):
                    with patch('lib.utils.safely_add_to_path', return_value=True):
                        result = prerequisites.is_tool_available(prereq)
                        assert result is True


class TestHomebrewInstallation:
    """Test Homebrew installation."""

    @patch('lib.utils.stream_command_output')
    def test_install_via_homebrew_success(self, mock_stream):
        """Test successful Homebrew installation."""
        mock_stream.return_value = (0, ["Installing package...", "Success!"])

        success, msg = prerequisites.install_via_homebrew("test-package")

        assert success is True
        assert "Installed test-package" in msg
        mock_stream.assert_called_once()

    @patch('lib.utils.stream_command_output')
    def test_install_via_homebrew_failure(self, mock_stream):
        """Test failed Homebrew installation."""
        mock_stream.return_value = (1, ["Error: Package not found"])

        success, msg = prerequisites.install_via_homebrew("bad-package")

        assert success is False
        assert "failed" in msg.lower()


class TestPipxInstallation:
    """Test pipx installation with SSL support."""

    @patch('lib.utils.stream_command_output')
    @patch('lib.utils.run_command')
    @patch('lib.utils.safely_add_to_path')
    def test_install_huggingface_hub_with_ssl(self, mock_path, mock_run, mock_stream):
        """Test HuggingFace CLI installation with pip-system-certs."""
        mock_stream.return_value = (0, ["Installing..."])
        mock_run.return_value = (0, "", "")
        mock_path.return_value = True

        success, msg = prerequisites.install_via_pipx("huggingface-hub[cli]")

        assert success is True
        # Verify pip-system-certs injection was attempted
        assert any("inject" in str(call) for call in mock_run.call_args_list)

    @patch('lib.utils.stream_command_output')
    @patch('lib.utils.run_command')
    @patch('lib.utils.safely_add_to_path')
    def test_install_regular_package(self, mock_path, mock_run, mock_stream):
        """Test installing non-HuggingFace package."""
        mock_stream.return_value = (0, ["installed successfully"])
        mock_run.return_value = (0, "", "")
        mock_path.return_value = True

        success, msg = prerequisites.install_via_pipx("some-package")

        assert success is True
        # Should not inject pip-system-certs for non-HF packages
        inject_calls = [call for call in mock_run.call_args_list if "inject" in str(call)]
        assert len(inject_calls) == 0


class TestBunInstallation:
    """Test bun installation with security validation."""

    @patch('lib.utils.create_secure_temp_file')
    @patch('lib.utils.run_command')
    @patch('lib.utils.stream_command_output')
    @patch('lib.utils.safely_add_to_path')
    def test_install_bun_success(self, mock_path, mock_stream, mock_run, mock_temp):
        """Test successful bun installation."""
        # Mock temp file
        temp_file = MagicMock()
        temp_file.read_text.return_value = "#!/bin/bash\necho Installing bun"
        temp_file.exists.return_value = True
        mock_temp.return_value = temp_file

        # Mock download
        mock_run.return_value = (0, "", "")

        # Mock installation
        mock_stream.return_value = (0, ["Installed bun successfully"])

        # Mock PATH addition
        mock_path.return_value = True

        success, msg = prerequisites.install_bun_official()

        assert success is True
        assert "Installed bun" in msg

    @patch('lib.utils.create_secure_temp_file')
    @patch('lib.utils.run_command')
    def test_install_bun_dangerous_pattern(self, mock_run, mock_temp):
        """Test bun installation rejects dangerous patterns."""
        # Mock temp file with dangerous content
        temp_file = MagicMock()
        temp_file.read_text.return_value = "#!/bin/bash\nrm -rf /\necho Installing bun"
        temp_file.exists.return_value = True
        mock_temp.return_value = temp_file

        # Mock download success
        mock_run.return_value = (0, "", "")

        # Mock user declining to continue
        with patch('lib.ui.prompt_yes_no', return_value=False):
            success, msg = prerequisites.install_bun_official()

            assert success is False
            assert "cancelled" in msg.lower()


class TestInstallAllPrerequisites:
    """Test installing all prerequisites."""

    @patch('shutil.which')
    @patch('lib.prerequisites.is_tool_available')
    def test_install_all_prerequisites_already_installed(self, mock_available, mock_which):
        """Test when all tools are already installed."""
        mock_which.return_value = "/usr/local/bin/brew"
        mock_available.return_value = True

        success, msg = prerequisites.install_all_prerequisites()

        assert success is True
        assert "successfully" in msg.lower()

    @patch('shutil.which')
    def test_install_all_prerequisites_no_homebrew(self, mock_which):
        """Test failure when Homebrew is not installed."""
        mock_which.return_value = None

        success, msg = prerequisites.install_all_prerequisites()

        assert success is False
        assert "Homebrew" in msg


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
