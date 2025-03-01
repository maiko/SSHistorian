# SSHistorian Database Migrations

This document describes the database migration system in SSHistorian, including how to create and manage migrations. 

> **Note:** For plugin-specific database migrations, see the [Plugin Database](Plugin_Database.md) documentation.

## Overview

SSHistorian uses a simple migration system to manage database schema changes over time. The migration system ensures that:

1. Database schema changes are tracked and applied consistently
2. Upgrades from older versions maintain data integrity
3. Table definitions are kept in separate files for better organization
4. Schema changes follow a clear, versioned process

## Migration Files

Migration files are stored in the `src/db/migrations` directory and follow this naming convention:

```
NNN_description.sql
```

Where:
- `NNN` is a 3-digit number that determines the order in which migrations are applied (001, 002, etc.)
- `description` is a brief description of what the migration does (e.g., `initial_schema`, `add_user_table`)

Each migration file is a SQL script that contains the schema changes to apply.

## Migration File Format

Migration files should follow this format:

```sql
-- SSHistorian - Migration Description
-- Migration ID: NNN_description
-- Created: YYYY-MM-DD

-- SQL statements to create or alter tables
CREATE TABLE example (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL
);
```

The header comments are important as they are used to identify and track the migration.

## How Migrations Are Applied

Migrations are applied automatically during the database initialization process:

1. When the application starts, it checks if the database exists
2. If the database does not exist, it creates it and runs all available migrations
3. If the database exists, it checks the current schema version against the expected version
4. If the versions don't match, it runs any missing migrations

The `run_migrations` function in `src/utils/migration.sh` handles this process.

## Creating a New Migration

To create a new migration:

1. Determine the next available migration number by checking the `src/db/migrations` directory
2. Create a new file with the naming convention `NNN_description.sql`
3. Add the appropriate header comments and SQL statements
4. Test the migration by running the application with a fresh database

Example:

```sql
-- SSHistorian - Add User Roles
-- Migration ID: 003_add_user_roles
-- Created: 2025-03-01

-- Create roles table
CREATE TABLE roles (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    created_at TEXT NOT NULL
);

-- Add role_id to existing users table
ALTER TABLE users ADD COLUMN role_id TEXT REFERENCES roles(id);
```

## Migrations Table

The migration system tracks applied migrations in a `migrations` table in the database:

```sql
CREATE TABLE migrations (
    migration_id TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL,
    description TEXT
);
```

When a migration is successfully applied, a record is added to this table to prevent the same migration from being applied again.

## Best Practices

1. **Never modify an existing migration file** that has been applied to any production database
2. For changes to existing tables, create a new migration that alters the table
3. Always test migrations on a copy of production data before deploying
4. Keep migrations small and focused on specific changes
5. Include down/rollback logic in comments when appropriate
6. Document complex migrations separately if needed
7. Use named parameters (`:name`) rather than positional placeholders (`?`) in SQL queries

## SQLite Parameter Binding

When writing SQL queries for SSHistorian, whether in migrations or code, follow these guidelines for parameter binding:

### Use Named Parameters

Always use named parameters (`:param_name`) rather than positional placeholders (`?`):

```sql
-- Good: Using named parameters
INSERT INTO sessions (id, host, timestamp) VALUES (:id, :host, :timestamp);

-- Avoid: Using positional placeholders
INSERT INTO sessions (id, host, timestamp) VALUES (?, ?, ?);
```

Named parameters are more reliable with the SQLite CLI, especially when using the parameter binding approach in SSHistorian.

### Parameter Binding in Code

When executing parameterized queries in code, use the appropriate helper functions:

- For main database: `query_db_params` in `src/db/database.sh`
- For plugin database: `query_plugin_db_params` in `src/plugins/plugin_db.sh`

Example:

```bash
# Query with named parameters
query_db_params "SELECT * FROM sessions WHERE host = :host AND timestamp > :time;" \
    ":host" "$hostname" \
    ":time" "$start_time"
```

This approach ensures proper escaping of special characters and prevents SQL injection attacks.

## Troubleshooting

If a migration fails:

1. The transaction will be rolled back automatically
2. An error message will be logged
3. The application will exit with a non-zero status code

To fix a failed migration:

1. Fix the issue in the migration file (if it's a syntax error)
2. If the migration was partially applied, you may need to manually adjust the database
3. Restart the application to retry the migration

For complex issues, you can manually manipulate the `migrations` table to mark migrations as applied or unapplied.