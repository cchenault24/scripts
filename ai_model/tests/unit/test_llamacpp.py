"""Unit tests for lib/llamacpp.py"""

from pathlib import Path
from unittest.mock import MagicMock, patch
import pytest

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from lib import llamacpp


class TestHFTokenHandling:
    """Test HuggingFace token handling."""

    @patch.dict('os.environ', {'HF_TOKEN': 'hf_test_token'})
    def test_ensure_hf_token_from_env(self):
        """Test token found in environment."""
        token = llamacpp.ensure_hf_token()

        assert token == 'hf_test_token'

    @patch.dict('os.environ', {}, clear=True)
    @patch('lib.ui.prompt_yes_no', return_value=False)
    def test_ensure_hf_token_skip(self, mock_prompt):
        """Test skipping token entry."""
        token = llamacpp.ensure_hf_token()

        assert token is None

    @patch.dict('os.environ', {}, clear=True)
    @patch('lib.ui.prompt_yes_no', return_value=True)
    @patch('builtins.input', return_value='hf_user_token')
    def test_ensure_hf_token_user_input(self, mock_input, mock_prompt):
        """Test user entering token."""
        token = llamacpp.ensure_hf_token()

        assert token == 'hf_user_token'


class TestLlamaCppInstallation:
    """Test llama.cpp installation via Homebrew."""

    @patch('shutil.which', return_value='/usr/local/bin/llama-server')
    @patch('lib.utils.run_command')
    def test_install_already_installed(self, mock_run, mock_which):
        """Test when llama.cpp is already installed."""
        mock_run.return_value = (0, "llama-server version b1234", "")

        success, msg = llamacpp.install_llama_cpp_homebrew()

        assert success is True
        assert "already installed" in msg.lower()

    @patch('shutil.which', return_value=None)
    @patch('lib.utils.stream_command_output')
    def test_install_success(self, mock_stream, mock_which):
        """Test successful installation."""
        # First call returns None (not installed), second returns path (installed)
        mock_which.side_effect = [None, '/usr/local/bin/llama-server']
        mock_stream.return_value = (0, ["Installed successfully"])

        with patch('lib.utils.run_command', return_value=(0, "llama-server version b1234", "")):
            success, msg = llamacpp.install_llama_cpp_homebrew()

            assert success is True
            assert "Installed llama.cpp" in msg

    @patch('shutil.which', return_value=None)
    @patch('lib.utils.stream_command_output')
    def test_install_failure(self, mock_stream, mock_which):
        """Test failed installation."""
        mock_stream.return_value = (1, ["Error: formula not found"])

        success, msg = llamacpp.install_llama_cpp_homebrew()

        assert success is False
        assert "failed" in msg.lower()


class TestModelDownload:
    """Test model download logic."""

    def test_parse_model_repo_valid(self):
        """Test valid model repo parsing."""
        model_repo = "ggml-org/gemma-4-26B-it-GGUF:Q4_K_M"

        # This would be inside download_model_from_hf
        assert ':' in model_repo
        repo_id, filename = model_repo.rsplit(':', 1)

        assert repo_id == "ggml-org/gemma-4-26B-it-GGUF"
        assert filename == "Q4_K_M"

    @patch('lib.utils.validate_repo_id', return_value=False)
    def test_download_invalid_repo_id(self, mock_validate):
        """Test download with invalid repo ID fails."""
        success, msg = llamacpp.download_model_from_hf("../../../etc/passwd:file")

        assert success is False
        assert "Invalid repository ID" in msg

    @patch('lib.utils.validate_repo_id', return_value=True)
    @patch('lib.utils.validate_filename', return_value=False)
    def test_download_invalid_filename(self, mock_val_file, mock_val_repo):
        """Test download with invalid filename fails."""
        success, msg = llamacpp.download_model_from_hf("org/repo:../../etc/passwd")

        assert success is False
        assert "Invalid filename" in msg

    @patch('lib.utils.validate_repo_id', return_value=True)
    @patch('lib.utils.validate_filename', return_value=True)
    @patch('lib.llamacpp.ensure_hf_token', return_value='hf_test')
    @patch('shutil.which', return_value='/usr/local/bin/hf')
    @patch('lib.utils.stream_command_output')
    def test_download_success(self, mock_stream, mock_which, mock_token, mock_val_file, mock_val_repo):
        """Test successful model download."""
        mock_stream.return_value = (0, ["Downloading... 100%", "Done"])

        # Mock cache directory exists
        with patch.object(Path, 'exists', return_value=True):
            success, msg = llamacpp.download_model_from_hf("org/repo:model")

            assert success is True
            assert "downloaded successfully" in msg.lower()

    @patch('lib.utils.validate_repo_id', return_value=True)
    @patch('lib.utils.validate_filename', return_value=True)
    @patch('lib.llamacpp.ensure_hf_token', return_value='hf_test')
    def test_download_hf_cli_not_found(self, mock_token, mock_val_file, mock_val_repo):
        """Test download fails when hf CLI not found."""
        with patch('shutil.which', return_value=None):
            with patch.object(Path, 'exists', return_value=False):
                success, msg = llamacpp.download_model_from_hf("org/repo:model")

                assert success is False
                assert "not found" in msg.lower()


class TestDiskSpaceCheck:
    """Test disk space validation."""

    @patch('shutil.disk_usage')
    def test_check_disk_space_sufficient(self, mock_disk):
        """Test sufficient disk space."""
        mock_disk.return_value = MagicMock(free=100 * 1024**3)  # 100GB

        success, msg = llamacpp.check_disk_space(50.0)  # Require 50GB

        assert success is True
        assert "available" in msg.lower()

    @patch('shutil.disk_usage')
    def test_check_disk_space_insufficient(self, mock_disk):
        """Test insufficient disk space."""
        mock_disk.return_value = MagicMock(free=10 * 1024**3)  # 10GB

        success, msg = llamacpp.check_disk_space(50.0)  # Require 50GB

        assert success is False
        assert "Insufficient" in msg


class TestChecksumVerification:
    """Test checksum verification in model downloads."""

    @patch('lib.utils.validate_repo_id', return_value=True)
    @patch('lib.utils.validate_filename', return_value=True)
    @patch('lib.llamacpp.ensure_hf_token', return_value='hf_test')
    @patch('shutil.which', return_value='/usr/local/bin/hf')
    @patch('lib.utils.verify_file_checksum', return_value=True)
    def test_download_with_checksum_verification(self, mock_verify, mock_which, mock_token, mock_val_file, mock_val_repo):
        """Test model download with checksum verification."""
        # Mock cached model exists
        with patch.object(Path, 'exists', return_value=True):
            with patch('glob.glob', return_value=['/path/to/model.gguf']):
                with patch.object(Path, 'stat') as mock_stat:
                    mock_stat.return_value = MagicMock(st_size=16 * 1024**3)  # 16GB

                    success, msg = llamacpp.download_model_from_hf(
                        "org/repo:model.gguf",
                        verify_checksum="abc123def456"
                    )

                    assert success is True
                    assert "verified" in msg.lower()
                    mock_verify.assert_called_once()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
