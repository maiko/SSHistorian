-- SSHistorian - Plugin Schema
-- Migration ID: 001_plugin_schema
-- Created: 2025-03-01
-- Description: Initial schema for plugin database

-- Plugin registration
CREATE TABLE IF NOT EXISTS plugins (
    id TEXT PRIMARY KEY,           -- Plugin unique identifier
    name TEXT NOT NULL,            -- Display name
    version TEXT NOT NULL,         -- Plugin version
    description TEXT,              -- Plugin description
    enabled INTEGER DEFAULT 0,     -- Whether plugin is enabled (1) or disabled (0)
    created_at TEXT NOT NULL,      -- When plugin was registered
    updated_at TEXT NOT NULL,      -- Last time plugin was updated
    has_pre_session_hook INTEGER DEFAULT 0,  -- Whether plugin has pre-session hook
    has_post_session_hook INTEGER DEFAULT 0  -- Whether plugin has post-session hook
);

-- Plugin settings
CREATE TABLE IF NOT EXISTS plugin_settings (
    plugin_id TEXT NOT NULL,       -- References plugins.id
    key TEXT NOT NULL,             -- Setting key
    value TEXT,                    -- Setting value
    description TEXT,              -- Setting description
    updated_at TEXT NOT NULL,      -- Last updated timestamp
    PRIMARY KEY (plugin_id, key),
    FOREIGN KEY (plugin_id) REFERENCES plugins(id)
);