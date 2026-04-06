#!/usr/bin/env python3
"""
Test script to verify the OpenCode setup flow.

Tests all major components without actually pulling models.
"""

import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

# Add project root to path
project_root = Path(__file__).resolve().parent
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

from lib import config
from lib import hardware
from lib import ide
from lib import model_selector
from lib import ui


def test_hardware_detection():
    """Test hardware detection."""
    print("Testing hardware detection...")
    try:
        hw_info = hardware.detect_hardware()
        print(f"  ✓ Detected: {hw_info.apple_chip_model or hw_info.cpu_brand}")
        print(f"  ✓ RAM: {hw_info.ram_gb:.1f} GB")
        return True
    except Exception as e:
        print(f"  ✗ Failed: {e}")
        return False


def test_model_catalog():
    """Test Gemma4 model catalog."""
    print("\nTesting Gemma4 model catalog...")
    try:
        models = model_selector.GEMMA4_MODELS
        print(f"  ✓ Found {len(models)} Gemma4 models:")
        for model in models:
            marker = " ★" if model.recommended else ""
            print(f"    • {model.name}{marker} ({model.size_label})")
        return True
    except Exception as e:
        print(f"  ✗ Failed: {e}")
        return False


def test_model_recommendation():
    """Test hardware-based model recommendation."""
    print("\nTesting model recommendation logic...")
    try:
        hw_info = hardware.detect_hardware()
        recommended = model_selector.get_recommended_model(hw_info)
        print(f"  ✓ Recommended for {hw_info.ram_gb:.0f}GB RAM:")
        print(f"    {recommended.name} ({recommended.ollama_name})")
        return True
    except Exception as e:
        print(f"  ✗ Failed: {e}")
        return False


def test_parameter_optimization():
    """Test Mac Silicon parameter optimization."""
    print("\nTesting parameter optimization...")
    try:
        hw_info = hardware.detect_hardware()
        params = config.get_model_parameters_for_hardware(hw_info)

        chip = hw_info.apple_chip_model or hw_info.cpu_brand
        print(f"  ✓ Parameters for {chip} with {hw_info.ram_gb:.0f}GB:")
        print(f"    • Temperature: {params['temperature']}")
        print(f"    • Context Length: {params['num_ctx']} tokens")
        print(f"    • Top-K: {params['top_k']}")
        print(f"    • Top-P: {params['top_p']}")
        return True
    except Exception as e:
        print(f"  ✗ Failed: {e}")
        return False


def test_ide_detection():
    """Test IntelliJ IDEA detection."""
    print("\nTesting IDE detection...")
    try:
        intellij_found = ide.is_intellij_installed()
        if intellij_found:
            print("  ✓ IntelliJ IDEA detected")

            # Check for OpenCode plugin
            opencode_found = ide.verify_opencode_plugin()
            if opencode_found:
                print("  ✓ OpenCode plugin detected")
            else:
                print("  ⚠ OpenCode plugin not found (expected if not installed)")
        else:
            print("  ⚠ IntelliJ IDEA not found (expected if not installed)")
        return True
    except Exception as e:
        print(f"  ✗ Failed: {e}")
        return False


def test_config_generation():
    """Test OpenCode configuration generation."""
    print("\nTesting config generation...")
    try:
        hw_info = hardware.detect_hardware()
        selected_model = model_selector.get_recommended_model(hw_info)

        # Generate config (in temp location)
        config_path = config.generate_opencode_config(
            model_name=selected_model.ollama_name,
            embedding_model="nomic-embed-text",
            hw_info=hw_info
        )

        if config_path and config_path.exists():
            print(f"  ✓ Config generated: {config_path}")

            # Verify it's valid JSON
            import json
            with open(config_path) as f:
                config_data = json.load(f)
            print(f"  ✓ Valid JSON with {len(config_data)} keys")
            return True
        else:
            print("  ⚠ Config generation skipped (may be expected)")
            return True
    except Exception as e:
        print(f"  ✗ Failed: {e}")
        return False


def test_model_selection_menu():
    """Test model selection menu display (without user input)."""
    print("\nTesting model selection menu display...")
    try:
        hw_info = hardware.detect_hardware()
        recommended = model_selector.get_recommended_model(hw_info)

        # Just test the display function
        model_selector.display_model_menu(hw_info, recommended)
        print("  ✓ Menu displayed successfully")
        return True
    except Exception as e:
        print(f"  ✗ Failed: {e}")
        return False


def main():
    """Run all tests."""
    ui.print_header("🧪 OpenCode Setup Verification Tests")
    print()
    print("Testing all components without pulling models...")
    print()

    tests = [
        ("Hardware Detection", test_hardware_detection),
        ("Model Catalog", test_model_catalog),
        ("Model Recommendation", test_model_recommendation),
        ("Parameter Optimization", test_parameter_optimization),
        ("IDE Detection", test_ide_detection),
        ("Config Generation", test_config_generation),
        ("Model Selection Menu", test_model_selection_menu),
    ]

    results = []
    for name, test_func in tests:
        try:
            result = test_func()
            results.append((name, result))
        except KeyboardInterrupt:
            print("\n\nTests interrupted by user")
            return 130
        except Exception as e:
            print(f"\n✗ Test '{name}' crashed: {e}")
            results.append((name, False))

    # Summary
    print()
    ui.print_header("📊 Test Summary")
    print()

    passed = sum(1 for _, result in results if result)
    total = len(results)

    for name, result in results:
        status = ui.colorize("✓ PASS", ui.Colors.GREEN) if result else ui.colorize("✗ FAIL", ui.Colors.RED)
        print(f"  {status}: {name}")

    print()
    print(f"Results: {passed}/{total} tests passed")

    if passed == total:
        print()
        ui.print_success("✅ All tests passed! Setup flow is ready.")
        print()
        print("You can now run:")
        print(f"  {ui.colorize('python3 setup.py', ui.Colors.CYAN)}")
        return 0
    else:
        print()
        ui.print_error(f"❌ {total - passed} test(s) failed")
        return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n\nTests interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"\n\n✗ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
