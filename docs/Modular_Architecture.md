# SSHistorian Modular Architecture

This document describes the modular architecture of the SSHistorian codebase, with a focus on separation of concerns and how the different components interact.

## Overview

SSHistorian follows a modular architecture that separates code into logical components with clear responsibilities. This approach provides several benefits:

1. **Maintainability**: Each module has a single, well-defined responsibility
2. **Testability**: Modules can be tested in isolation with clear interfaces
3. **Extensibility**: New features can be added by extending existing modules or adding new ones
4. **Readability**: Code organization makes it easier to understand the system

## Core Architecture

The application is organized into several key layers:

```
src/
├── bin/           # Executable scripts
├── config/        # Configuration management
├── core/          # Core business logic
│   ├── ssh/       # SSH-related functionality
│   └── ...
├── db/            # Database management
│   ├── core/      # Database core operations
│   ├── migration/ # Schema migrations
│   ├── models/    # Legacy model location
│   └── ...
├── models/        # Model layer (database entities)
│   ├── session/   # Session-related models
│   └── ...
├── plugins/       # Plugin system
│   └── ...
└── utils/         # Utility functions
```

## Module Responsibilities

### Configuration Layer

**`config/config.sh`**

- Manages application configuration
- Provides functions to get and set configuration values
- Handles configuration migration from legacy formats
- Uses the database as the configuration store

### Database Layer

The database layer is split into three main components:

**`db/core/db_core.sh`**
- Low-level database operations
- Connection management
- Transaction handling
- Parameter binding for secure queries

**`db/migration/migration.sh`**
- Schema versioning
- Migration execution
- Schema verification

**`db/database.sh`**
- Integrates all database components
- Provides a unified API for the rest of the application

### Model Layer

Models represent database entities with their associated logic. They are split into focused modules:

**`models/session/session_model.sh`**
- Core session operations (create, update, get, delete)
- Session listing and filtering
- File management for session logs

**`models/session/session_tags.sh`**
- Tag management for sessions
- Tag-based search and filtering
- Auto-tagging functionality

**`models/session.sh`**
- Integrates session model components

### Core Business Logic

**`core/ssh/ssh_handler.sh`**
- SSH command execution
- Session initiation and setup
- Plugin hook integration

**`core/ssh/session_recorder.sh`**
- Session recording
- Platform-specific recording implementation
- File management for logs

**`core/ssh/session_replay.sh`**
- Session replay functionality
- Encryption handling for secured logs
- Multiple replay formats (terminal, HTML)

**`core/ssh.sh`**
- Integrates SSH functionality

### Plugin System

**`plugins/plugin_manager.sh`**
- Plugin registration and lifecycle management
- Plugin settings management

**`plugins/plugin_db.sh`**
- Database operations for plugin data

**`plugins/plugin_hooks.sh`**
- Hook registration and execution
- Plugin timeouts and error handling

### Utility Layer

**`utils/common.sh`**
- Shared utility functions

**`utils/constants.sh`**
- Application constants and globals

**`utils/errors.sh`**
- Error handling and reporting
- Error code definitions
- Cleanup operations for error recovery

**`utils/logging.sh`**
- Logging functions for different levels
- Log formatting and output

## Dependency Flow

The dependency flow between modules is designed to be hierarchical to avoid circular dependencies:

```
                    +-------------+
                    |   utils/    |
                    +-------------+
                          ^
                          |
                    +-------------+
                    |    db/      |
                    +-------------+
                     ^          ^
              +------+          +------+
              |                        |
     +-------------+            +-------------+
     |   models/   |            |   config/   |
     +-------------+            +-------------+
              ^                        ^
              |                        |
              +------------+-----------+
                           |
                     +-------------+
                     |    core/    |
                     +-------------+
                           ^
                           |
                     +-------------+
                     |  plugins/   |
                     +-------------+
```

## Module Integration

Modules are integrated through a "facade" pattern:
- Each component has a main module (like `ssh.sh`) that sources all of its sub-components
- This gives external code a single entry point for accessing features
- Internal modules have clear dependencies that are explicitly imported

## Future Extensions

This architecture supports several extension points:

1. **New Models**: Add new entity types by creating new model modules
2. **Additional Plugins**: Extend functionality through the plugin system
3. **Alternative Storage**: The database layer can be extended for different backends
4. **UI Components**: New UI modules can be added while reusing existing business logic

## Best Practices

When maintaining or extending this codebase:

1. **Respect Module Boundaries**: Don't bypass the designated entry point for a module
2. **Maintain Separation of Concerns**: Keep each module focused on its specific responsibility
3. **Use Parameter Binding**: Always use parameter binding for database queries to prevent SQL injection
4. **Handle Errors Properly**: Use the error handling system to ensure resources are cleaned up
5. **Validate Inputs**: Validate and sanitize all inputs, especially file paths
6. **Document Interfaces**: Clearly document function parameters and return values

By following these principles, the codebase remains maintainable and extensible as it grows.