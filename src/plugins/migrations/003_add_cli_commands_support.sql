-- Add CLI commands support to plugins table
ALTER TABLE plugins ADD COLUMN has_cli_commands INTEGER DEFAULT 0;

-- Add a comment to explain the migration
PRAGMA user_version = 3;

-- In SQLite, there's no proper way to store migration metadata, so we're using user_version
-- This ensures the migration system knows this has been applied