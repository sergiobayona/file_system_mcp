# frozen_string_literal: true

require "vector_mcp"
require "pathname"
require "fileutils"
require "json"
require "find"

# Main module for the FileSystem MCP server
module FileSystemMCP
  # Require components in dependency order
  require_relative 'filesystem_mcp/utils/diff_utils'
  require_relative 'filesystem_mcp/schemas/file_schemas'
  require_relative 'filesystem_mcp/schemas/directory_schemas'
  require_relative 'filesystem_mcp/schemas/search_schemas'
  require_relative 'filesystem_mcp/schemas/info_schemas'
  require_relative 'filesystem_mcp/tools/base_tool'
  require_relative 'filesystem_mcp/tools/file_operations'
  require_relative 'filesystem_mcp/tools/directory_operations'
  require_relative 'filesystem_mcp/tools/search_operations'
  require_relative 'filesystem_mcp/tools/info_operations'
  require_relative 'filesystem_mcp/config'
  require_relative 'filesystem_mcp/server'
end