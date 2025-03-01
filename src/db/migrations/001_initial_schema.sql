-- SSHistorian - Initial Database Schema (v1)
-- Migration ID: 001_initial_schema
-- Created: 2025-03-01

-- Version tracking
CREATE TABLE IF NOT EXISTS schema_info (
    version TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- Session information
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,                -- UUID
    host TEXT NOT NULL,                 -- Hostname/IP
    timestamp TEXT NOT NULL,            -- ISO format
    command TEXT NOT NULL,              -- Full SSH command
    user TEXT NOT NULL,                 -- Local user who initiated connection
    remote_user TEXT,                   -- User on remote server
    exit_code INTEGER,                  -- SSH command exit code
    duration INTEGER,                   -- Session duration in seconds
    created_at TEXT NOT NULL,           -- In ISO format
    log_path TEXT NOT NULL,             -- Path to .log file (relative to logs dir)
    timing_path TEXT NOT NULL,          -- Path to .timing file (relative to logs dir)
    notes TEXT                          -- Any additional notes
);

-- Session tags
CREATE TABLE IF NOT EXISTS tags (
    session_id TEXT NOT NULL,
    tag TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (session_id, tag),
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);

-- Configuration settings
CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT,
    type TEXT NOT NULL,                 -- 'string', 'boolean', 'integer', 'path', etc.
    default_value TEXT,
    updated_at TEXT NOT NULL
);

-- Encryption information
CREATE TABLE IF NOT EXISTS encryption_info (
    session_id TEXT PRIMARY KEY,
    public_key_fingerprint TEXT NOT NULL,  -- Fingerprint of the key used
    encrypted_at TEXT NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);