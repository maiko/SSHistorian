# Plugin Migrations Directory

This directory is reserved for plugin-specific database migrations. Plugin migrations follow the same format as core migrations but are specific to extending the database schema for individual plugins that require additional tables beyond the standard plugin infrastructure.

## When to use plugin migrations

Most plugins don't need their own migrations as they can use the standard plugin tables:
- `plugins` - For plugin registration
- `plugin_settings` - For plugin configuration

These tables are created by the core migration `002_plugins_schema.sql`.

## Creating a plugin migration

If your plugin needs additional database tables:

1. Create a migration file in this directory following the naming pattern: `XXX_plugin_name_migration.sql`
2. Follow the SQL migration format used in core migrations
3. Include a header comment with the migration ID and description
4. Ensure proper error handling and transaction safety

## Migration loading

Plugin migrations are loaded and applied through the plugin manager's `initialize_plugin_schema()` function, which is called when the plugin system starts up.

Migrations are only applied when a plugin is enabled, preventing unnecessary schema changes for unused functionality.