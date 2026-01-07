# Zsh Setup API Documentation

## Overview

This document provides API reference for the zsh-setup modular system. All functions use the `zsh_setup::` namespace prefix.

## Module Structure

```
zsh_setup::
  ├── core::
  │   ├── bootstrap::
  │   ├── config::
  │   ├── logger::
  │   └── errors::
  ├── state::
  │   └── store::
  ├── system::
  │   ├── package_manager::
  │   ├── shell::
  │   └── validation::
  ├── plugins::
  │   ├── registry::
  │   ├── resolver::
  │   ├── installer::
  │   └── manager::
  ├── config::
  │   ├── validator::
  │   ├── backup::
  │   └── generator::
  └── utils::
      ├── network::
      └── filesystem::
```

## Core Modules

### bootstrap

Module loading and initialization.

#### `zsh_setup::core::bootstrap::init()`
Initialize the zsh-setup environment.

**Returns:** 0 on success, 1 on failure

**Example:**
```bash
source "$ZSH_SETUP_ROOT/lib/core/bootstrap.sh"
zsh_setup::core::bootstrap::init
```

#### `zsh_setup::core::bootstrap::load_module(module)`
Load a module by name.

**Arguments:**
- `module` - Module name (e.g., "core::config")

**Returns:** 0 on success, 1 on failure

**Example:**
```bash
zsh_setup::core::bootstrap::load_module "plugins::manager"
```

#### `zsh_setup::core::bootstrap::load_modules(module1, module2, ...)`
Load multiple modules.

**Arguments:**
- `module1, module2, ...` - Module names to load

**Returns:** 0 if all succeed, 1 on first failure

### config

Configuration management.

#### `zsh_setup::core::config::get(key, [default])`
Get a configuration value.

**Arguments:**
- `key` - Configuration key
- `default` - Optional default value

**Returns:** Configuration value or default

**Example:**
```bash
local ohmyzsh_dir=$(zsh_setup::core::config::get oh_my_zsh_dir)
```

#### `zsh_setup::core::config::set(key, value)`
Set a configuration value.

**Arguments:**
- `key` - Configuration key
- `value` - Configuration value

### logger

Logging interface.

#### `zsh_setup::core::logger::info(message)`
Log an info message.

#### `zsh_setup::core::logger::error(message)`
Log an error message.

#### `zsh_setup::core::logger::success(message)`
Log a success message.

#### `zsh_setup::core::logger::warn(message)`
Log a warning message.

### errors

Error handling and retry logic.

#### `zsh_setup::core::errors::execute_with_retry(description, command...)`
Execute a command with retry logic.

**Arguments:**
- `description` - Description of the operation
- `command...` - Command and arguments to execute

**Returns:** Exit code of the command

**Example:**
```bash
zsh_setup::core::errors::execute_with_retry "Installing package" brew install package
```

## State Management

### store

State persistence and retrieval.

#### `zsh_setup::state::store::init([script_dir])`
Initialize the state file.

**Arguments:**
- `script_dir` - Optional script directory for metadata

#### `zsh_setup::state::store::add_plugin(name, method, version)`
Add a plugin to the installed list.

**Arguments:**
- `name` - Plugin name
- `method` - Installation method (git, brew, etc.)
- `version` - Plugin version

#### `zsh_setup::state::store::get_installed_plugins()`
Get list of installed plugins.

**Returns:** Newline-separated list of plugin names

## Plugin System

### registry

Plugin registry management.

#### `zsh_setup::plugins::registry::load()`
Load plugin configurations from files.

#### `zsh_setup::plugins::registry::get(plugin_name, field)`
Get plugin information.

**Arguments:**
- `plugin_name` - Name of the plugin
- `field` - Field to retrieve (type, url, description, or all)

**Returns:** Requested field value

### installer

Plugin installation methods.

#### `zsh_setup::plugins::installer::install_git(name, url, [type])`
Install a git-based plugin.

**Arguments:**
- `name` - Plugin name
- `url` - Git repository URL
- `type` - Plugin type (plugin or theme)

**Returns:** 0 on success, 1 on failure

### manager

Plugin orchestration.

#### `zsh_setup::plugins::manager::install_list(plugin1, plugin2, ...)`
Install a list of plugins.

**Arguments:**
- `plugin1, plugin2, ...` - Plugin names to install

## System Operations

### validation

System validation and requirements checking.

#### `zsh_setup::system::validation::check_requirements()`
Check if system requirements are met.

**Returns:** 0 if requirements met, 1 otherwise

#### `zsh_setup::system::validation::check_privileges([force_prompt])`
Check for sudo/admin privileges.

**Arguments:**
- `force_prompt` - If true, prompt user even in non-interactive mode

**Returns:** 0 if privileges available, 1 otherwise

### package_manager

Package manager abstraction.

#### `zsh_setup::system::package_manager::install(package_name, [description])`
Install a system package.

**Arguments:**
- `package_name` - Package name
- `description` - Optional description for logging

**Returns:** 0 on success, 1 on failure

### shell

Shell management.

#### `zsh_setup::system::shell::change_default()`
Change the default shell to Zsh.

**Returns:** 0 on success, 1 on failure

## Configuration

### validator

Configuration validation.

#### `zsh_setup::config::validator::validate_all([root])`
Validate all configuration files.

**Arguments:**
- `root` - Optional root directory (defaults to ZSH_SETUP_ROOT)

**Returns:** 0 if valid, 1 if errors found

### generator

.zshrc generation.

#### `zsh_setup::config::generator::generate()`
Generate .zshrc configuration.

**Returns:** 0 on success, 1 on failure

## Usage Examples

### Running the Script

The main entry point is `zsh-setup` in the project root:

```bash
./zsh-setup install
./zsh-setup update
./zsh-setup status
```

### Basic Initialization

```bash
# Load bootstrap
source "$ZSH_SETUP_ROOT/lib/core/bootstrap.sh"

# Initialize
zsh_setup::core::bootstrap::init

# Load modules
zsh_setup::core::bootstrap::load_module "plugins::manager"
```

### Installing Plugins

```bash
# Load required modules
zsh_setup::core::bootstrap::load_modules \
    plugins::registry \
    plugins::manager

# Load plugin registry
zsh_setup::plugins::registry::load

# Install plugins
zsh_setup::plugins::manager::install_list "powerlevel10k" "zsh-autosuggestions"
```

### Managing State

```bash
# Initialize state
zsh_setup::state::store::init

# Add installed plugin
zsh_setup::state::store::add_plugin "powerlevel10k" "git" "abc123"

# Get installed plugins
zsh_setup::state::store::get_installed_plugins
```

## Dependency Graph

```
core::bootstrap
  ├── core::config
  ├── core::logger
  └── core::errors

plugins::manager
  ├── plugins::registry
  ├── plugins::resolver
  └── plugins::installer
      ├── system::package_manager
      └── utils::network

config::generator
  └── state::store
```

## Error Handling

All functions follow consistent error handling:
- Return 0 on success
- Return 1 on failure
- Use `zsh_setup::core::errors::handle()` for error reporting
- Use `zsh_setup::core::errors::execute_with_retry()` for retryable operations

## Notes

- All functions are namespaced to prevent conflicts
- Modules are loaded lazily and cached
- State is persisted in JSON format
- Configuration supports environment variable overrides
