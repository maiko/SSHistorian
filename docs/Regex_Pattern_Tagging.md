# SSHistorian - Regex Pattern Tagging

SSHistorian's Auto Tag plugin supports powerful regex-based pattern matching for automatically tagging SSH sessions. This document explains how to configure and use this feature.

## Overview

The regex tagging feature allows you to define regular expression patterns that are matched against:
- The hostname
- The command
- The remote user

When a match is found, a tag is applied to the session. You can use capture groups in your regex patterns to create dynamic tags based on the matched content.

## Configuration

To enable regex-based tagging:

1. Enable the Auto Tag plugin (it's enabled by default)
2. Set the `enable_regex` setting to `true`:
   ```
   sshistorian plugin set autotag enable_regex true
   ```
3. Define your regex patterns in JSON format:
   ```
   sshistorian plugin set autotag regex_patterns '[{"pattern":"regex1","tag":"tag1"},{"pattern":"regex2","tag":"tag2"}]'
   ```

## Pattern Format

The regex patterns are defined in a JSON array of objects with the following structure:

```json
[
  {
    "pattern": "regex_pattern",
    "tag": "tag_template",
    "description": "Optional description"
  }
]
```

- `pattern`: A regular expression pattern in Bash regex syntax
- `tag`: The tag to apply, which can include capture group references
- `description`: Optional description for documentation purposes

### Capture Groups

You can use capture groups in your regex patterns and reference them in your tag using `$1`, `$2`, etc.:

```json
{
  "pattern": "^db([0-9]+)-([a-z]+)",
  "tag": "database_$2_$1"
}
```

For example, with the above pattern, a hostname like `db01-prod` would be tagged as `database_prod_01`.

## Example Patterns

Here are some useful regex pattern examples:

```json
[
  {
    "pattern": "^db[0-9]+-([a-z]+)",
    "tag": "database_$1",
    "description": "Tags database servers with their environment (e.g., db01-prod → database_prod)"
  },
  {
    "pattern": "^(app|web|cache)[0-9]+-([a-z]+)",
    "tag": "server_$1_$2",
    "description": "Tags server type with environment (e.g., app01-prod → server_app_prod)"
  },
  {
    "pattern": "-p\\s+([0-9]+)",
    "tag": "port_$1",
    "description": "Tags sessions by non-standard port (e.g., -p 2222 → port_2222)"
  }
]
```

The example file `examples/autotag_regex_patterns.json` contains a more comprehensive set of patterns you can use as a reference.

## Usage

Once configured, the regex tagging system works automatically with any new SSH sessions. You do not need to manually tag sessions - the system will match patterns and apply tags based on your configuration.

To check the tags applied to a session:

```
sshistorian session show [session_id]
```

## Troubleshooting

If your regex patterns aren't working as expected:

1. Enable debug logging: `export DEBUG=true`
2. Run your SSH command through SSHistorian
3. Check the logs for regex matching debug info

Common issues:
- JSON syntax errors in the regex_patterns configuration
- Regex pattern escaping (remember to double-escape backslashes)
- Capture group references not in the expected format

## Advanced Usage

For very complex tagging rules that cannot be expressed as regex patterns, consider using the custom tagging rules script (`enable_custom_rules` setting) which provides full programmatic control over tagging logic.