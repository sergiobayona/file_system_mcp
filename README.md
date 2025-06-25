# Filesystem MCP Server

Ruby server implementing Model Context Protocol (MCP) for filesystem operations using the [vector_mcp](https://rubygems.org/gems/vector_mcp) gem.

## Features

- File operations: read, write, edit, move
- Directory operations: create, list
- Advanced search with filtering and sorting
- Bulk metadata operations
- Optional authentication and authorization
- Secure filesystem boundaries using MCP roots

## Installation

1. Install Ruby 3.1+ and bundler
2. Clone this repository
3. Run `bundle install`

## Usage

### Basic Mode
```bash
ruby file_system_mcp.rb ~/Documents ~/Desktop
```

### Secure Mode (with authentication)
```bash
FILESYSTEM_MCP_API_KEY=your-secret-key ruby file_system_mcp.rb --enable-auth ~/Documents
```

## Claude Desktop Configuration

Add to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "ruby",
      "args": [
        "/path/to/file_system_mcp.rb",
        "~/Documents",
        "~/Desktop"
      ]
    }
  }
}
```

For secure mode:
```json
{
  "mcpServers": {
    "filesystem": {
      "command": "ruby",
      "args": [
        "/path/to/file_system_mcp.rb",
        "--enable-auth",
        "~/Documents"
      ],
      "env": {
        "FILESYSTEM_MCP_API_KEY": "your-secret-key"
      }
    }
  }
}
```

## Tools

### File Operations
- **read_file** - Read complete file contents
- **read_multiple_files** - Read multiple files at once
- **write_file** - Create/overwrite files
- **edit_file** - Make precise text replacements with diff preview
- **move_file** - Move/rename files and directories

### Directory Operations
- **list_directory** - List contents with optional metadata
- **create_directory** - Create directories recursively

### Search Operations
- **search_files** - Basic recursive search with patterns
- **find_files** - Advanced search with sorting, filtering, and metadata

### Info Operations
- **get_file_info** - Get detailed file/directory metadata
- **get_bulk_file_info** - Get metadata for multiple files efficiently

## Security

The server enforces filesystem boundaries using MCP roots - it can only access directories specified as command-line arguments. 

Optional authentication adds API key verification for all operations.

## Requirements

- Ruby 3.1+
- vector_mcp gem v0.3.1+