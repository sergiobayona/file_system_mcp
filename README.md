# Filesystem MCP Server

Ruby server implementing Model Context Protocol (MCP) for filesystem operations using the [vector_mcp](https://rubygems.org/gems/vector_mcp) gem.

## Features

- Read/write files
- Create/list/delete directories
- Move files/directories
- Search files
- Get file metadata

**Note**: The server will only allow operations within directories specified via `args`.

## API

### Resources

- `file://system`: File system operations interface

### Tools

- **read_file**
  - Read complete contents of a file
  - Input: `path` (string)
  - Reads complete file contents with UTF-8 encoding

- **read_multiple_files**
  - Read multiple files simultaneously
  - Input: `paths` (string[])
  - Failed reads won't stop the entire operation

- **write_file**
  - Create new file or overwrite existing (exercise caution with this)
  - Inputs:
    - `path` (string): File location
    - `content` (string): File content

- **edit_file**
  - Make exact text (substring) replacements in a file.
  - Features:
    - Line-based and multi-line content matching
    - Multiple simultaneous edits with correct positioning
    - Git-style diff output with context
    - Preview changes with dry run mode
  - Inputs:
    - `path` (string): File to edit
    - `edits` (array): List of edit operations
      - `oldText` (string): Text to search for (can be substring)
      - `newText` (string): Text to replace with
    - `dryRun` (boolean): Preview changes without applying (default: false)
  - Returns detailed diff and match information for dry runs, otherwise applies changes
  - Best Practice: Always use dryRun first to preview changes before applying them

- **create_directory**
  - Create new directory or ensure it exists
  - Input: `path` (string)
  - Creates parent directories if needed
  - Succeeds silently if directory exists

- **list_directory**
  - List directory contents as a JSON array, with each item containing 'name' and 'type' ('file' or 'directory').
  - Inputs:
    - `path` (string): Directory path to list
    - `include_metadata` (boolean, optional): Include file metadata (size, dates, permissions) in response (default: false)
  - When `include_metadata` is true, adds: `size`, `modified`, `created`, `permissions`

- **move_file**
  - Move or rename files and directories
  - Inputs:
    - `source` (string)
    - `destination` (string)
  - Fails if destination exists

- **search_files**
  - Recursively search for files/directories
  - Inputs:
    - `path` (string): Starting directory
    - `pattern` (string): Search pattern
    - `excludePatterns` (string[]): Exclude any patterns. Glob formats are supported.
  - Case-insensitive matching
  - Returns full paths to matches

- **find_files**
  - Advanced file finder with sorting, filtering, and metadata
  - Inputs:
    - `path` (string): Starting directory for search
    - `sort_by` (string, optional): Sort by "modified", "created", "size", or "name" (default: "name")
    - `order` (string, optional): Sort order "asc" or "desc" (default: "asc")
    - `limit` (integer, optional): Maximum number of results to return
    - `file_types` (string[], optional): Filter by file extensions (e.g., ["txt", "pdf", "jpg"])
    - `modified_after` (string, optional): Only files modified after this ISO date
    - `modified_before` (string, optional): Only files modified before this ISO date
    - `min_size` (integer, optional): Minimum file size in bytes
    - `max_size` (integer, optional): Maximum file size in bytes
    - `include_directories` (boolean, optional): Include directories in results (default: true)
  - Returns JSON with metadata: path, name, type, size, modified, created, permissions
  - Examples:
    - `find_files(path="Desktop", sort_by="modified", order="desc", limit=1)` - Most recently modified file
    - `find_files(path="Documents", file_types=["pdf"], min_size=1000000)` - Large PDF files
    - `find_files(path="Photos", modified_after="2025-01-01T00:00:00Z", sort_by="size")` - Recent photos by size

- **get_file_info**
  - Get detailed file/directory metadata
  - Input: `path` (string)
  - Returns:
    - Size
    - Creation time
    - Modified time
    - Access time
    - Type (file/directory)
    - Permissions

- **get_bulk_file_info**
  - Retrieve metadata for multiple files/directories in a single operation
  - Inputs:
    - `paths` (string[]): Array of file/directory paths to get information about
    - `include_errors` (boolean, optional): Include error information for inaccessible files (default: true)
  - Returns JSON with summary statistics and detailed metadata for each file
  - More efficient than multiple `get_file_info` calls
  - Handles errors gracefully - continues processing other files if some fail
  - Example: `get_bulk_file_info(paths=["file1.txt", "dir1/", "file2.pdf"])`

- **list_allowed_directories**
  - List all directories the server is allowed to access
  - No input required
  - Returns:
    - Directories that this server can read/write from

## Usage with Claude Desktop
Add this to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "ruby",
      "args": [
        "/Users/your_username/file_system_mcp/file_system_mcp.rb",
        "/Users/your_username/Desktop",
        "/path/to/other/allowed/dir"
      ]
    }
  }
}
```

**About the `args` array**

1. The first element is the absolute path to the `file_system_mcp.rb` script.  
2. Every subsequent element is an absolute path to a directory that the server is allowed to read from and write to.  

Make sure to replace **all** of these paths with locations that exist on *your* machine before starting Claude Desktop.
