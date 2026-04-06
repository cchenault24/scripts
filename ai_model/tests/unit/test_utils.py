"""Unit tests for lib/utils.py"""

import os
import tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch, mock_open
import pytest

# Add project root to path
import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from lib import utils


class TestSecureTempFiles:
    """Test secure temporary file and directory creation."""

    def test_create_secure_temp_dir(self):
        """Test secure temp directory creation."""
        temp_dir = utils.create_secure_temp_dir("test-prefix")

        assert temp_dir.exists()
        assert temp_dir.is_dir()
        assert temp_dir.name.startswith("test-prefix-")

        # Verify permissions (0700)
        stat_info = temp_dir.stat()
        assert oct(stat_info.st_mode)[-3:] == "700"

        # Cleanup
        temp_dir.rmdir()

    def test_create_secure_temp_file(self):
        """Test secure temp file creation."""
        temp_file = utils.create_secure_temp_file("test-prefix", ".txt")

        assert temp_file.exists()
        assert temp_file.is_file()
        assert temp_file.name.startswith("test-prefix-")
        assert temp_file.suffix == ".txt"

        # Verify permissions (0600)
        stat_info = temp_file.stat()
        assert oct(stat_info.st_mode)[-3:] == "600"

        # Cleanup
        temp_file.unlink()


class TestInputValidation:
    """Test input validation functions."""

    def test_validate_repo_id_valid(self):
        """Test valid repository IDs."""
        assert utils.validate_repo_id("ggml-org/gemma-4-26B-it-GGUF")
        assert utils.validate_repo_id("facebook/bart-large")
        assert utils.validate_repo_id("user_name/repo-name")

    def test_validate_repo_id_invalid(self):
        """Test invalid repository IDs."""
        assert not utils.validate_repo_id("../../../etc/passwd")
        assert not utils.validate_repo_id("repo-without-org")
        assert not utils.validate_repo_id("org//double-slash")
        assert not utils.validate_repo_id("org/repo; rm -rf /")

    def test_validate_filename_valid(self):
        """Test valid filenames."""
        assert utils.validate_filename("model.gguf")
        assert utils.validate_filename("gemma-4-26B-Q4_K_M.gguf")

    def test_validate_filename_invalid(self):
        """Test invalid filenames (path traversal)."""
        assert not utils.validate_filename("../../../etc/passwd.gguf")
        assert not utils.validate_filename("/etc/passwd.gguf")
        assert not utils.validate_filename("model.txt")  # Not .gguf
        assert not utils.validate_filename("model\x00.gguf")  # Null byte


class TestPathSecurity:
    """Test PATH security validation."""

    def test_safely_add_to_path_valid(self, tmp_path):
        """Test adding valid directory to PATH."""
        test_dir = tmp_path / "bin"
        test_dir.mkdir()

        original_path = os.environ.get("PATH", "")

        result = utils.safely_add_to_path(test_dir)
        assert result is True
        assert str(test_dir) in os.environ["PATH"]

        # Restore PATH
        os.environ["PATH"] = original_path

    def test_safely_add_to_path_nonexistent(self, tmp_path):
        """Test adding non-existent directory fails."""
        fake_dir = tmp_path / "nonexistent"

        result = utils.safely_add_to_path(fake_dir)
        assert result is False

    @patch('os.getuid', return_value=1000)
    def test_safely_add_to_path_wrong_owner(self, mock_getuid, tmp_path):
        """Test adding directory with wrong owner fails."""
        test_dir = tmp_path / "bin"
        test_dir.mkdir()

        # Mock stat to show different owner
        with patch.object(Path, 'stat') as mock_stat:
            mock_stat.return_value = MagicMock(st_uid=999, st_mode=0o755)  # Different UID

            result = utils.safely_add_to_path(test_dir)
            assert result is False


class TestChecksumVerification:
    """Test checksum verification."""

    def test_verify_file_checksum_valid(self, tmp_path):
        """Test valid checksum verification."""
        test_file = tmp_path / "test.txt"
        test_file.write_text("Hello, World!")

        # SHA-256 of "Hello, World!"
        expected_hash = "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f"

        assert utils.verify_file_checksum(test_file, expected_hash)

    def test_verify_file_checksum_invalid(self, tmp_path):
        """Test invalid checksum fails."""
        test_file = tmp_path / "test.txt"
        test_file.write_text("Hello, World!")

        wrong_hash = "0" * 64

        assert not utils.verify_file_checksum(test_file, wrong_hash)


class TestBackupFiles:
    """Test file backup functionality."""

    def test_backup_file_if_exists(self, tmp_path):
        """Test timestamped backup creation."""
        original = tmp_path / "original.txt"
        original.write_text("Original content")

        backup = utils.backup_file_if_exists(original, force=True)

        assert backup is not None
        assert backup.exists()
        assert backup.name.startswith("original.backup.")  # Fixed: actual format
        assert backup.read_text() == "Original content"

    def test_backup_file_nonexistent(self, tmp_path):
        """Test backup of non-existent file returns None."""
        fake_file = tmp_path / "nonexistent.txt"

        backup = utils.backup_file_if_exists(fake_file, force=True)
        assert backup is None


class TestRetryLogic:
    """Test retry with exponential backoff."""

    def test_retry_success_first_attempt(self):
        """Test successful function on first attempt."""
        mock_func = MagicMock(return_value="success")

        result = utils.retry_with_backoff(mock_func, max_retries=3)

        assert result == "success"
        assert mock_func.call_count == 1

    def test_retry_success_after_failures(self):
        """Test success after initial failures."""
        mock_func = MagicMock(side_effect=[IOError(), IOError(), "success"])

        result = utils.retry_with_backoff(
            mock_func,
            max_retries=3,
            initial_delay=0.01,
            exceptions=(IOError,)
        )

        assert result == "success"
        assert mock_func.call_count == 3

    def test_retry_all_failures(self):
        """Test all retries fail."""
        mock_func = MagicMock(side_effect=IOError("Network error"))

        with pytest.raises(IOError, match="Network error"):
            utils.retry_with_backoff(
                mock_func,
                max_retries=3,
                initial_delay=0.01,
                exceptions=(IOError,)
            )

        assert mock_func.call_count == 3


class TestCommandExecution:
    """Test command execution utilities."""

    @patch('subprocess.run')
    def test_run_command_success(self, mock_run):
        """Test successful command execution."""
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout="output",
            stderr=""
        )

        code, stdout, stderr = utils.run_command(["echo", "hello"])

        assert code == 0
        assert stdout == "output"
        assert stderr == ""

    @patch('subprocess.run')
    def test_run_command_clean_env(self, mock_run):
        """Test clean_env removes SSH_AUTH_SOCK."""
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout="",
            stderr=""
        )

        with patch.dict('os.environ', {'SSH_AUTH_SOCK': '/tmp/ssh-agent'}):
            utils.run_command(["ollama", "list"], clean_env=True)

            # Verify subprocess.run was called with env that excludes SSH_AUTH_SOCK
            call_kwargs = mock_run.call_args[1]
            assert 'env' in call_kwargs
            assert 'SSH_AUTH_SOCK' not in call_kwargs['env']

    @patch('subprocess.Popen')
    def test_stream_command_output(self, mock_popen):
        """Test streaming command output."""
        mock_process = MagicMock()
        mock_process.stdout = iter(["Line 1\n", "Line 2\n", "Line 3\n"])
        mock_process.returncode = 0
        mock_process.wait.return_value = 0
        mock_popen.return_value = mock_process

        code, lines = utils.stream_command_output(
            ["echo", "test"],
            keywords=["Line"],
            show_progress=False
        )

        assert code == 0
        assert len(lines) == 3
        assert "Line 1\n" in lines


class TestProgressBar:
    """Test terminal progress bar rendering."""

    @patch('sys.stdout')
    def test_render_progress_bar(self, mock_stdout):
        """Test progress bar rendering."""
        utils.render_progress_bar("Downloading", 50, bar_length=20)

        # Verify write was called
        assert mock_stdout.write.called

        # Get the written text
        written = mock_stdout.write.call_args[0][0]
        assert "Downloading" in written
        assert "50%" in written


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
