# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture

This is a Ruby-based MCP (Model Context Protocol) server that provides secure filesystem operations. It uses the modern `vector_mcp` gem (v0.3.0+) and implements the MCP roots specification for filesystem boundaries.

### Key Security Model
- **MCP Roots**: Uses the standard MCP roots functionality to define filesystem boundaries
- **Framework Security**: All path validation and security is handled by the vector_mcp framework
- **No Custom Validation**: Eliminates custom path validation in favor of MCP standards

### Core Components

**Main Server (`file_system_mcp.rb`)**:
- Uses modern `VectorMCP.new(name:, version:)` initialization pattern
- Registers filesystem roots using `register_root_from_path()` for each allowed directory
- Registers tools using simplified `register_tool` API with JSON schema validation
- Built-in error handling and structured logging
- Framework handles all filesystem security automatically

**Tool Categories**:
- **File Operations**: read_file, read_multiple_files, write_file, edit_file
- **Directory Operations**: create_directory, list_directory
- **File System Navigation**: move_file, search_files, get_file_info
- **Root Management**: Framework provides built-in root management tools

## Development Commands

**Install dependencies:**
```bash
bundle install
```

**Run the server (requires allowed directories as arguments):**
```bash
ruby file_system_mcp.rb /path/to/allowed/dir1 /path/to/allowed/dir2
```

**Development with Ruby LSP:**
The Gemfile includes `ruby-lsp` for language server support.

## Modern Framework Features

**MCP Roots Registration**: Uses the standard MCP approach for filesystem boundaries:
```ruby
# Register each allowed directory as a root
validated_dirs.each_with_index do |dir_info, index|
  root_name = "#{dir_info[:name]}_#{index}"
  server.register_root_from_path(dir_info[:expanded], name: root_name)
end
```

**Tool Registration**: Uses the new block-based API:
```ruby
server.register_tool(
  name: "tool_name",
  description: "Tool description",
  input_schema: {
    type: "object",
    properties: { ... },
    required: [...]
  }
) do |args|
  # Tool implementation - framework handles path validation
end
```

**Automatic Input Validation**: Framework automatically validates tool arguments against JSON schemas, providing better error messages and type safety.

**Framework Security**: All filesystem security is handled by the vector_mcp framework through the roots system.

**Structured Logging**: Uses `VectorMCP.logger` for consistent logging across all operations.

## Key Implementation Details

**MCP-Compliant Architecture**: Uses the MCP roots specification instead of custom validation logic.

**Simplified Code**: Eliminated ~100+ lines of custom path validation code in favor of framework features.

**Edit Tool Features**: 
- Supports exact text replacement with multiple simultaneous edits
- Simplified diff output (basic format - can be enhanced with diff-lcs if needed)
- Includes dry-run mode for preview (`dryRun: true`)

**Search Implementation**: Uses Ruby's `File.fnmatch` with case-insensitive glob patterns and exclude pattern support.

**Modernization Benefits**:
- MCP specification compliance
- Dramatically simplified codebase
- Framework-handled security
- Automatic input validation
- Better error messages
- Future compatibility with MCP specification updates

## Security Considerations

- Uses MCP roots specification for filesystem boundary enforcement
- Framework automatically handles all path validation and security
- No custom security logic required - leverages battle-tested framework features
- Symlink resolution and directory traversal protection handled by the framework
- Additional security features (authentication/authorization) available via framework options

## Compatibility

The modernized server maintains full backward compatibility with existing Claude Desktop configurations while providing enhanced features and better maintainability.