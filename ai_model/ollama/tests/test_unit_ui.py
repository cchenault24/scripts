"""
Unit tests for lib/ui.py - UI utilities for terminal output.

Tests cover:
- Colors class constants
- colorize function
- print_* functions (header, success, error, warning, info)
- clear_screen function
- prompt_* functions (with mocked input)
"""

import pytest
from unittest.mock import patch, MagicMock
import io
import sys

from lib import ui
from lib.ui import Colors, colorize, print_header, print_subheader, print_success
from lib.ui import print_error, print_warning, print_info, print_step, clear_screen
from lib.ui import prompt_yes_no, prompt_choice, prompt_multi_choice


class TestColors:
    """Tests for Colors class constants."""
    
    def test_reset_code_exists(self):
        """Verify RESET escape code is defined."""
        assert Colors.RESET == "\033[0m"
    
    def test_bold_code_exists(self):
        """Verify BOLD escape code is defined."""
        assert Colors.BOLD == "\033[1m"
    
    def test_color_codes_are_strings(self):
        """Verify all color codes are strings."""
        color_attrs = ['RESET', 'BOLD', 'DIM', 'RED', 'GREEN', 'YELLOW', 
                       'BLUE', 'MAGENTA', 'CYAN', 'WHITE', 'BG_BLUE', 'BG_GREEN']
        for attr in color_attrs:
            value = getattr(Colors, attr)
            assert isinstance(value, str), f"{attr} is not a string"
            assert value.startswith("\033["), f"{attr} is not a valid escape code"


class TestColorize:
    """Tests for colorize function."""
    
    def test_colorize_adds_reset(self):
        """Verify colorize adds RESET at the end."""
        result = colorize("test", Colors.RED)
        assert result.endswith(Colors.RESET)
    
    def test_colorize_applies_color(self):
        """Verify colorize applies the color code at start."""
        result = colorize("hello", Colors.GREEN)
        assert result.startswith(Colors.GREEN)
        assert "hello" in result
    
    def test_colorize_empty_string(self):
        """Test colorizing an empty string."""
        result = colorize("", Colors.BLUE)
        assert result == f"{Colors.BLUE}{Colors.RESET}"
    
    def test_colorize_combined_colors(self):
        """Test colorizing with combined color codes."""
        combined = Colors.RED + Colors.BOLD
        result = colorize("text", combined)
        assert result.startswith(combined)


class TestPrintFunctions:
    """Tests for print_* functions."""
    
    def test_print_header_output(self, capsys):
        """Test print_header produces output."""
        print_header("Test Header")
        captured = capsys.readouterr()
        assert "Test Header" in captured.out
        assert "═" in captured.out  # Header separator
    
    def test_print_subheader_output(self, capsys):
        """Test print_subheader produces output."""
        print_subheader("Test Subheader")
        captured = capsys.readouterr()
        assert "Test Subheader" in captured.out
        assert "─" in captured.out  # Subheader separator
    
    def test_print_success_output(self, capsys):
        """Test print_success produces success indicator."""
        print_success("Operation succeeded")
        captured = capsys.readouterr()
        assert "Operation succeeded" in captured.out
        assert "✓" in captured.out
    
    def test_print_error_output(self, capsys):
        """Test print_error produces error indicator."""
        print_error("Operation failed")
        captured = capsys.readouterr()
        assert "Operation failed" in captured.out
        assert "✗" in captured.out
    
    def test_print_warning_output(self, capsys):
        """Test print_warning produces warning indicator."""
        print_warning("Be careful")
        captured = capsys.readouterr()
        assert "Be careful" in captured.out
        assert "⚠" in captured.out
    
    def test_print_info_output(self, capsys):
        """Test print_info produces info indicator."""
        print_info("For your information")
        captured = capsys.readouterr()
        assert "For your information" in captured.out
        assert "ℹ" in captured.out
    
    def test_print_step_output(self, capsys):
        """Test print_step shows step numbers."""
        print_step(2, 5, "Installing")
        captured = capsys.readouterr()
        assert "[2/5]" in captured.out
        assert "Installing" in captured.out


class TestClearScreen:
    """Tests for clear_screen function."""
    
    @patch('os.system')
    @patch('platform.system', return_value='Linux')
    def test_clear_screen_linux(self, mock_platform, mock_system):
        """Test clear_screen uses 'clear' on Linux."""
        clear_screen()
        mock_system.assert_called_once_with("clear")
    
    @patch('os.system')
    @patch('platform.system', return_value='Darwin')
    def test_clear_screen_macos(self, mock_platform, mock_system):
        """Test clear_screen uses 'clear' on macOS."""
        clear_screen()
        mock_system.assert_called_once_with("clear")
    
    @patch('os.system')
    @patch('platform.system', return_value='Windows')
    def test_clear_screen_windows(self, mock_platform, mock_system):
        """Test clear_screen uses 'cls' on Windows."""
        clear_screen()
        mock_system.assert_called_once_with("cls")


class TestPromptYesNo:
    """Tests for prompt_yes_no function."""
    
    @patch('builtins.input', return_value='y')
    def test_yes_response(self, mock_input):
        """Test 'y' returns True."""
        result = prompt_yes_no("Continue?")
        assert result is True
    
    @patch('builtins.input', return_value='yes')
    def test_yes_full_word(self, mock_input):
        """Test 'yes' returns True."""
        result = prompt_yes_no("Continue?")
        assert result is True
    
    @patch('builtins.input', return_value='n')
    def test_no_response(self, mock_input):
        """Test 'n' returns False."""
        result = prompt_yes_no("Continue?")
        assert result is False
    
    @patch('builtins.input', return_value='no')
    def test_no_full_word(self, mock_input):
        """Test 'no' returns False."""
        result = prompt_yes_no("Continue?")
        assert result is False
    
    @patch('builtins.input', return_value='')
    def test_empty_uses_default_true(self, mock_input):
        """Test empty input uses default (True)."""
        result = prompt_yes_no("Continue?", default=True)
        assert result is True
    
    @patch('builtins.input', return_value='')
    def test_empty_uses_default_false(self, mock_input):
        """Test empty input uses default (False)."""
        result = prompt_yes_no("Continue?", default=False)
        assert result is False
    
    @patch('builtins.input', return_value='Y')
    def test_uppercase_y(self, mock_input):
        """Test uppercase 'Y' works."""
        result = prompt_yes_no("Continue?")
        assert result is True
    
    @patch('builtins.input', side_effect=['invalid', 'y'])
    def test_invalid_then_valid(self, mock_input, capsys):
        """Test invalid input prompts again."""
        result = prompt_yes_no("Continue?")
        assert result is True
        captured = capsys.readouterr()
        assert "Please enter" in captured.out


class TestPromptChoice:
    """Tests for prompt_choice function."""
    
    @patch('builtins.input', return_value='1')
    def test_select_first_option(self, mock_input):
        """Test selecting first option."""
        choices = ["Option A", "Option B", "Option C"]
        result = prompt_choice("Pick one:", choices)
        assert result == 0
    
    @patch('builtins.input', return_value='2')
    def test_select_second_option(self, mock_input):
        """Test selecting second option."""
        choices = ["Option A", "Option B", "Option C"]
        result = prompt_choice("Pick one:", choices)
        assert result == 1
    
    @patch('builtins.input', return_value='')
    def test_empty_uses_default(self, mock_input):
        """Test empty input uses default."""
        choices = ["Option A", "Option B"]
        result = prompt_choice("Pick one:", choices, default=1)
        assert result == 1
    
    @patch('builtins.input', side_effect=['5', '1'])
    def test_out_of_range_reprompts(self, mock_input, capsys):
        """Test out-of-range selection reprompts."""
        choices = ["Option A", "Option B"]
        result = prompt_choice("Pick one:", choices)
        assert result == 0
        captured = capsys.readouterr()
        assert "Please enter a number" in captured.out
    
    @patch('builtins.input', side_effect=['abc', '2'])
    def test_non_numeric_reprompts(self, mock_input, capsys):
        """Test non-numeric input reprompts."""
        choices = ["Option A", "Option B"]
        result = prompt_choice("Pick one:", choices)
        assert result == 1


class TestPromptMultiChoice:
    """Tests for prompt_multi_choice function."""
    
    @patch('builtins.input', return_value='1,2')
    def test_select_multiple(self, mock_input):
        """Test selecting multiple options."""
        choices = [("A", "desc A", False), ("B", "desc B", False), ("C", "desc C", False)]
        result = prompt_multi_choice("Pick:", choices)
        assert 0 in result
        assert 1 in result
        assert 2 not in result
    
    @patch('builtins.input', return_value='a')
    def test_select_all(self, mock_input):
        """Test 'a' selects all options."""
        choices = [("A", "", False), ("B", "", False), ("C", "", False)]
        result = prompt_multi_choice("Pick:", choices)
        assert result == [0, 1, 2]
    
    @patch('builtins.input', return_value='n')
    def test_select_none(self, mock_input):
        """Test 'n' selects none."""
        choices = [("A", "", True), ("B", "", True)]
        result = prompt_multi_choice("Pick:", choices, min_selections=0)
        assert result == []
    
    @patch('builtins.input', return_value='')
    def test_empty_uses_defaults(self, mock_input):
        """Test empty input uses default selections."""
        choices = [("A", "", True), ("B", "", False), ("C", "", True)]
        result = prompt_multi_choice("Pick:", choices)
        assert 0 in result  # Default True
        assert 1 not in result  # Default False
        assert 2 in result  # Default True
    
    @patch('builtins.input', side_effect=['n', '1'])
    def test_min_selections_enforced(self, mock_input, capsys):
        """Test minimum selections is enforced."""
        choices = [("A", "", False), ("B", "", False)]
        result = prompt_multi_choice("Pick:", choices, min_selections=1)
        assert len(result) >= 1
        captured = capsys.readouterr()
        assert "at least" in captured.out
    
    @patch('builtins.input', return_value='1-3')
    def test_range_selection(self, mock_input):
        """Test range selection (e.g., '1-3')."""
        choices = [("A", "", False), ("B", "", False), ("C", "", False), ("D", "", False)]
        result = prompt_multi_choice("Pick:", choices)
        assert 0 in result
        assert 1 in result
        assert 2 in result
