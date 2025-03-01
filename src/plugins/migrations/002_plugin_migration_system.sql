-- SSHistorian - Plugin Migration System
-- Migration ID: 002_plugin_migration_system
-- Created: 2025-03-01
-- Description: Initial migration for plugin system

-- This migration is used to test the plugin migration system
-- No actual schema changes needed since base schema is created by plugin_db.sh

-- Example of extension table for a plugin
CREATE TABLE IF NOT EXISTS plugin_migration_test (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    created_at TEXT NOT NULL
);

-- Insert test record to verify migration is working
INSERT INTO plugin_migration_test (id, name, description, created_at)
VALUES (1, 'Test Migration', 'This record confirms that the plugin migration system is working correctly', datetime('now'));