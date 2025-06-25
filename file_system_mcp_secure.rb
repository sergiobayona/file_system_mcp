#!/usr/bin/env ruby
# frozen_string_literal: true

require "vector_mcp"
require "pathname"
require "fileutils"
require "json"
require "find"

# Configuration & Argument Parsing
args = ARGV.dup

# Parse optional security flags
enable_auth = args.delete("--enable-auth")
api_key = nil

if enable_auth
  api_key = ENV["FILESYSTEM_MCP_API_KEY"]
  if api_key.nil? || api_key.empty?
    warn "Error: --enable-auth requires FILESYSTEM_MCP_API_KEY environment variable"
    exit(1)
  end
end

if args.empty?
  warn "Usage: #{$PROGRAM_NAME} [--enable-auth] <allowed-directory-1> [allowed-directory-2 ...]"
  warn "Example: #{$PROGRAM_NAME} ~/projects /var/data"
  warn "         FILESYSTEM_MCP_API_KEY=secret #{$PROGRAM_NAME} --enable-auth ~/projects"
  exit(1)
end

# Helper to expand ~
def expand_home(filepath)
  filepath.start_with?('~') ? File.expand_path(filepath) : filepath
end

# Prepare directories for root registration - framework will validate
dirs_to_register = args.map.with_index do |dir, index|
  expanded = expand_home(dir)
  { original: dir, expanded: expanded, name: "#{File.basename(expanded)}_#{index}" }
end

# Initialize server with modern API
server = VectorMCP.new(name: "VectorMCP::FileSystemServer::Secure", version: "0.5.0")

# Configure logging
logger = VectorMCP.logger

logger.info "MCP Filesystem Server (Secure Mode, Roots-based) starting"
logger.info "Authentication: #{enable_auth ? 'Enabled' : 'Disabled'}"
logger.info "Registering roots for: #{dirs_to_register.map { |d| d[:original] }.join(', ')}"

# Register filesystem roots - framework handles all validation
dirs_to_register.each do |dir_info|
  begin
    server.register_root_from_path(dir_info[:expanded], name: dir_info[:name])
    logger.info "Registered root '#{dir_info[:name]}' for #{dir_info[:original]}"
  rescue StandardError => e
    logger.error "Failed to register root for #{dir_info[:original]}: #{e.message}"
    exit(1)
  end
end

# Security configuration
if enable_auth
  server.enable_authentication!
  server.add_api_key(api_key, user_id: "filesystem_user", capabilities: %w[read write admin])
  
  server.enable_authorization!
  
  # Define authorization policies
  server.authorize_tool("read_file") { |context| context.authenticated? }
  server.authorize_tool("read_multiple_files") { |context| context.authenticated? }
  server.authorize_tool("list_directory") { |context| context.authenticated? }
  server.authorize_tool("get_file_info") { |context| context.authenticated? }
  server.authorize_tool("get_bulk_file_info") { |context| context.authenticated? }
  server.authorize_tool("search_files") { |context| context.authenticated? }
  server.authorize_tool("find_files") { |context| context.authenticated? }
  
  # Write operations require authentication
  server.authorize_tool("write_file") { |context| context.authenticated? }
  server.authorize_tool("edit_file") { |context| context.authenticated? }
  server.authorize_tool("create_directory") { |context| context.authenticated? }
  server.authorize_tool("move_file") { |context| context.authenticated? }
  
  logger.info "Security policies configured"
end

# Simplified diff function
def create_unified_diff(old_content, new_content, file_path)
  if old_content == new_content
    "No changes detected.\n"
  else
    old_lines = old_content.lines.size
    new_lines = new_content.lines.size
    "--- a/#{file_path}\n+++ b/#{file_path}\n@@ -1,#{old_lines} +1,#{new_lines} @@\n" +
    "Content changed (#{old_lines} -> #{new_lines} lines)\n"
  end
end

# Tool: read_file
server.register_tool(
  name: "read_file",
  description: "Read the complete contents of a single file. Only works within registered roots. Requires authentication in secure mode.",
  input_schema: {
    type: "object",
    properties: {
      path: { type: "string", description: "Path to the file to read" }
    },
    required: ["path"]
  }
) do |args|
  begin
    logger.debug "Reading file: #{args['path']}"
    File.read(args["path"])
  rescue Errno::ENOENT => e
    logger.error "File not found: #{e.message}"
    "Error: Path not found - #{e.message}"
  rescue Errno::EACCES => e
    logger.error "Permission denied: #{e.message}"
    "Error: Permission denied - #{e.message}"
  rescue StandardError => e
    logger.error "Unexpected error: #{e.class} - #{e.message}"
    "Error: An unexpected server error occurred."
  end
end

# Tool: read_multiple_files
server.register_tool(
  name: "read_multiple_files",
  description: "Read the contents of multiple files. Returns content prefixed by path, or an error message per file. Requires authentication in secure mode.",
  input_schema: {
    type: "object",
    properties: {
      paths: {
        type: "array",
        items: { type: "string" },
        description: "Array of file paths to read"
      }
    },
    required: ["paths"]
  }
) do |args|
  results = args["paths"].map do |path|
    begin
      logger.debug "Reading multiple file: #{path}"
      content = File.read(path)
      "#{path}:\n#{content}\n"
    rescue StandardError => e
      logger.error "Error reading #{path}: #{e.message}"
      "#{path}: Error: #{e.message}"
    end
  end
  results.join("\n---\n")
end

# Tool: write_file
server.register_tool(
  name: "write_file",
  description: "Create a new file or overwrite an existing file with content. Use with caution. Requires authentication in secure mode.",
  input_schema: {
    type: "object",
    properties: {
      path: { type: "string", description: "Path where to write the file" },
      content: { type: "string", description: "Content to write to the file" }
    },
    required: ["path", "content"]
  }
) do |args|
  begin
    logger.debug "Writing file: #{args['path']}"
    File.write(args["path"], args["content"])
    "Successfully wrote to #{args["path"]}"
  rescue StandardError => e
    logger.error "Error writing file: #{e.message}"
    "Error: #{e.message}"
  end
end

# Tool: edit_file
server.register_tool(
  name: "edit_file",
  description: "Make exact text replacements in a file. Use dryRun=true to preview changes. Requires authentication in secure mode.",
  input_schema: {
    type: "object",
    properties: {
      path: { type: "string", description: "Path to the file to edit" },
      edits: {
        type: "array",
        items: {
          type: "object",
          properties: {
            oldText: { type: "string", description: "Text to search for - must match exactly" },
            newText: { type: "string", description: "Text to replace with" }
          },
          required: ["oldText", "newText"]
        },
        description: "Array of edit operations"
      },
      dryRun: { 
        type: "boolean", 
        description: "Preview changes using diff format", 
        default: false 
      }
    },
    required: ["path", "edits"]
  }
) do |args|
  begin
    edits = args["edits"]
    dry_run = args["dryRun"] || false
    
    logger.debug "Editing file: #{args['path']} (dryRun: #{dry_run})"
    
    original_content = File.read(args["path"])
    modified_content = original_content.dup
    
    edits.each do |edit|
      old_text = edit["oldText"]
      new_text = edit["newText"]
      unless modified_content.gsub!(old_text, new_text)
        logger.warn "Edit failed: Text not found in #{args['path']}: #{old_text.inspect}"
      end
    end
    
    diff_output = create_unified_diff(original_content, modified_content, args["path"])
    
    unless dry_run
      if original_content != modified_content
        File.write(args["path"], modified_content)
        logger.info "Applied edits to #{args['path']}"
      else
        logger.info "No actual changes made to #{args['path']}"
      end
    end
    
    "```diff\n#{diff_output}```\n\n#{dry_run ? 'Dry run complete. No changes were written.' : 'Edits applied successfully.'}"
    
  rescue StandardError => e
    logger.error "Error editing file: #{e.message}"
    "Error: #{e.message}"
  end
end

# Tool: create_directory
server.register_tool(
  name: "create_directory",
  description: "Create a directory, including parent directories if needed. Requires authentication in secure mode.",
  input_schema: {
    type: "object",
    properties: {
      path: { type: "string", description: "Path of the directory to create" }
    },
    required: ["path"]
  }
) do |args|
  begin
    logger.debug "Creating directory: #{args['path']}"
    FileUtils.mkdir_p(args["path"])
    "Successfully created directory #{args["path"]}"
  rescue StandardError => e
    logger.error "Error creating directory: #{e.message}"
    "Error: #{e.message}"
  end
end

# Tool: list_directory
server.register_tool(
  name: "list_directory",
  description: "List files and directories in a path as a JSON array. Requires authentication in secure mode.",
  input_schema: {
    type: "object",
    properties: {
      path: { type: "string", description: "Path to the directory to list" },
      include_metadata: { 
        type: "boolean", 
        description: "Include file metadata (size, dates) in the response",
        default: false 
      }
    },
    required: ["path"]
  }
) do |args|
  begin
    unless Pathname.new(args["path"]).directory?
      raise Errno::ENOTDIR, args["path"]
    end
    
    include_metadata = args["include_metadata"] || false
    logger.debug "Listing directory: #{args['path']} (metadata: #{include_metadata})"
    
    entries = Dir.children(args["path"]).map do |entry_name|
      entry_path = File.join(args["path"], entry_name)
      
      begin
        is_directory = File.directory?(entry_path)
        entry = {
          type: is_directory ? 'directory' : 'file',
          name: entry_name
        }
        
        if include_metadata
          begin
            stats = File.stat(entry_path)
            entry[:size] = stats.size
            entry[:modified] = stats.mtime.utc.iso8601(3)
            entry[:created] = stats.birthtime.utc.iso8601(3)
            entry[:permissions] = format("%o", stats.mode & 0o777)
          rescue StandardError => e
            logger.warn "Could not get metadata for #{entry_path}: #{e.message}"
            # Continue without metadata for this entry
          end
        end
        
        entry
      rescue Errno::ENOENT, Errno::EACCES
        { type: 'error', name: entry_name }
      end
    end.sort_by { |e| [e[:type], e[:name].downcase] }
    
    JSON.pretty_generate(entries)
  rescue StandardError => e
    logger.error "Error listing directory: #{e.message}"
    "Error: #{e.message}"
  end
end

# Tool: move_file
server.register_tool(
  name: "move_file",
  description: "Move or rename a file or directory. Fails if the destination exists. Requires authentication in secure mode.",
  input_schema: {
    type: "object",
    properties: {
      source: { type: "string", description: "Source path" },
      destination: { type: "string", description: "Destination path" }
    },
    required: ["source", "destination"]
  }
) do |args|
  begin
    if Pathname.new(args["destination"]).exist?
      raise Errno::EEXIST, "Destination path '#{args["destination"]}' already exists."
    end
    
    logger.debug "Moving: #{args['source']} -> #{args['destination']}"
    FileUtils.mv(args["source"], args["destination"])
    "Successfully moved #{args["source"]} to #{args["destination"]}"
  rescue StandardError => e
    logger.error "Error moving file: #{e.message}"
    "Error: #{e.message}"
  end
end

# Tool: search_files
server.register_tool(
  name: "search_files",
  description: "Recursively search for files/directories matching a glob pattern. Requires authentication in secure mode.",
  input_schema: {
    type: "object",
    properties: {
      path: { type: "string", description: "Starting directory for search" },
      pattern: { type: "string", description: "Glob pattern (e.g., '*.txt', 'data/**/log?.log')" },
      excludePatterns: {
        type: "array",
        items: { type: "string" },
        default: [],
        description: "Glob patterns to exclude"
      }
    },
    required: ["path", "pattern"]
  }
) do |args|
  begin
    root_path = Pathname.new(args["path"])
    pattern = args["pattern"]
    exclude_patterns = args["excludePatterns"] || []
    
    unless root_path.directory?
      raise Errno::ENOTDIR, args["path"]
    end
    
    logger.debug "Searching under #{args['path']} for pattern '#{pattern}'"
    
    results = []
    root_path.find do |pathname|
      begin
        relative_path = pathname.relative_path_from(root_path).to_s
        
        is_excluded = exclude_patterns.any? do |exclude_pattern|
          File.fnmatch(exclude_pattern, relative_path, File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_CASEFOLD) ||
          File.fnmatch(exclude_pattern, pathname.basename.to_s, File::FNM_DOTMATCH | File::FNM_CASEFOLD)
        end
        next if is_excluded
        
        if File.fnmatch(pattern, pathname.basename.to_s, File::FNM_DOTMATCH | File::FNM_CASEFOLD)
          results << pathname.to_s
        end
      rescue Errno::EACCES, Errno::ENOENT
        Find.prune if pathname.directory?
        next
      end
    end
    
    results.empty? ? "No matches found" : results.join("\n")
  rescue StandardError => e
    logger.error "Error searching files: #{e.message}"
    "Error: #{e.message}"
  end
end

# Tool: find_files
server.register_tool(
  name: "find_files",
  description: "Advanced file finder with sorting, filtering, and metadata. Recursively searches directories with powerful filtering options. Requires authentication in secure mode.",
  input_schema: {
    type: "object",
    properties: {
      path: { type: "string", description: "Starting directory for search" },
      sort_by: { 
        type: "string", 
        enum: ["modified", "created", "size", "name"],
        description: "Sort results by specified criteria",
        default: "name"
      },
      order: {
        type: "string",
        enum: ["asc", "desc"],
        description: "Sort order (ascending or descending)",
        default: "asc"
      },
      limit: {
        type: "integer",
        minimum: 1,
        description: "Maximum number of results to return"
      },
      file_types: {
        type: "array",
        items: { type: "string" },
        description: "Filter by file extensions (e.g., ['txt', 'pdf', 'jpg'])"
      },
      modified_after: {
        type: "string",
        description: "Only include files modified after this ISO date (e.g., '2025-01-01T00:00:00Z')"
      },
      modified_before: {
        type: "string",
        description: "Only include files modified before this ISO date (e.g., '2025-12-31T23:59:59Z')"
      },
      min_size: {
        type: "integer",
        minimum: 0,
        description: "Minimum file size in bytes"
      },
      max_size: {
        type: "integer",
        minimum: 0,
        description: "Maximum file size in bytes"
      },
      include_directories: {
        type: "boolean",
        description: "Include directories in results",
        default: true
      }
    },
    required: ["path"]
  }
) do |args|
  begin
    root_path = Pathname.new(args["path"])
    
    unless root_path.directory?
      raise Errno::ENOTDIR, args["path"]
    end
    
    # Parse parameters
    sort_by = args["sort_by"] || "name"
    order = args["order"] || "asc"
    limit = args["limit"]
    file_types = args["file_types"]&.map(&:downcase)
    modified_after = args["modified_after"] ? Time.parse(args["modified_after"]) : nil
    modified_before = args["modified_before"] ? Time.parse(args["modified_before"]) : nil
    min_size = args["min_size"]
    max_size = args["max_size"]
    include_directories = args["include_directories"].nil? ? true : args["include_directories"]
    
    logger.debug "Finding files under #{args['path']} (sort: #{sort_by} #{order}, limit: #{limit})"
    
    results = []
    root_path.find do |pathname|
      begin
        next if pathname == root_path # Skip the root directory itself
        
        is_directory = pathname.directory?
        
        # Skip directories if not requested
        next if is_directory && !include_directories
        
        # Get file stats
        stats = pathname.stat
        
        # Apply file type filter (only for files)
        if !is_directory && file_types
          ext = pathname.extname.downcase.sub(/^\./, '')
          next unless file_types.include?(ext)
        end
        
        # Apply date filters
        if modified_after && stats.mtime < modified_after
          next
        end
        
        if modified_before && stats.mtime > modified_before
          next
        end
        
        # Apply size filters (only for files)
        if !is_directory
          if min_size && stats.size < min_size
            next
          end
          
          if max_size && stats.size > max_size
            next
          end
        end
        
        # Build result entry
        entry = {
          path: pathname.to_s,
          name: pathname.basename.to_s,
          type: is_directory ? "directory" : "file",
          size: stats.size,
          modified: stats.mtime.utc.iso8601(3),
          created: stats.birthtime.utc.iso8601(3),
          permissions: format("%o", stats.mode & 0o777)
        }
        
        results << entry
        
      rescue Errno::EACCES, Errno::ENOENT => e
        logger.warn "Cannot access #{pathname}: #{e.message}"
        Find.prune if pathname.directory?
        next
      end
    end
    
    # Sort results
    results.sort! do |a, b|
      case sort_by
      when "modified"
        comparison = Time.parse(a[:modified]) <=> Time.parse(b[:modified])
      when "created"
        comparison = Time.parse(a[:created]) <=> Time.parse(b[:created])
      when "size"
        comparison = a[:size] <=> b[:size]
      when "name"
        comparison = a[:name].downcase <=> b[:name].downcase
      else
        comparison = a[:name].downcase <=> b[:name].downcase
      end
      
      order == "desc" ? -comparison : comparison
    end
    
    # Apply limit
    results = results.first(limit) if limit
    
    # Format output
    if results.empty?
      "No files found matching the criteria"
    else
      JSON.pretty_generate({
        total_found: results.length,
        files: results
      })
    end
    
  rescue ArgumentError => e
    logger.error "Invalid parameter: #{e.message}"
    "Error: Invalid parameter - #{e.message}"
  rescue StandardError => e
    logger.error "Error finding files: #{e.message}"
    "Error: #{e.message}"
  end
end

# Tool: get_file_info
server.register_tool(
  name: "get_file_info",
  description: "Retrieve metadata (size, dates, type, permissions) for a file or directory. Requires authentication in secure mode.",
  input_schema: {
    type: "object",
    properties: {
      path: { type: "string", description: "Path to get information about" }
    },
    required: ["path"]
  }
) do |args|
  begin
    stats = File.stat(args["path"])
    info = {
      path: args["path"],
      size: stats.size,
      created: stats.birthtime,
      modified: stats.mtime,
      accessed: stats.atime,
      isDirectory: stats.directory?,
      isFile: stats.file?,
      isSymlink: stats.symlink?,
      permissions: format("%o", stats.mode & 0o777),
      uid: stats.uid,
      gid: stats.gid
    }
    info.map { |k, v| "#{k}: #{v}" }.join("\n")
  rescue StandardError => e
    logger.error "Error getting file info: #{e.message}"
    "Error: #{e.message}"
  end
end

# Tool: get_bulk_file_info
server.register_tool(
  name: "get_bulk_file_info",
  description: "Retrieve metadata for multiple files or directories in a single operation. More efficient than multiple get_file_info calls. Requires authentication in secure mode.",
  input_schema: {
    type: "object",
    properties: {
      paths: {
        type: "array",
        items: { type: "string" },
        description: "Array of file/directory paths to get information about"
      },
      include_errors: {
        type: "boolean",
        description: "Include error information for inaccessible files",
        default: true
      }
    },
    required: ["paths"]
  }
) do |args|
  begin
    paths = args["paths"]
    include_errors = args["include_errors"].nil? ? true : args["include_errors"]
    
    logger.debug "Getting bulk file info for #{paths.length} paths"
    
    results = []
    successful_count = 0
    error_count = 0
    
    paths.each do |path|
      begin
        stats = File.stat(path)
        
        file_info = {
          path: path,
          success: true,
          size: stats.size,
          modified: stats.mtime.utc.iso8601(3),
          created: stats.birthtime.utc.iso8601(3),
          accessed: stats.atime.utc.iso8601(3),
          type: stats.directory? ? "directory" : "file",
          isDirectory: stats.directory?,
          isFile: stats.file?,
          isSymlink: stats.symlink?,
          permissions: format("%o", stats.mode & 0o777),
          uid: stats.uid,
          gid: stats.gid
        }
        
        results << file_info
        successful_count += 1
        
      rescue Errno::ENOENT => e
        error_count += 1
        if include_errors
          results << {
            path: path,
            success: false,
            error: "File not found",
            error_type: "ENOENT",
            error_message: e.message
          }
        end
        logger.warn "File not found: #{path}"
        
      rescue Errno::EACCES => e
        error_count += 1
        if include_errors
          results << {
            path: path,
            success: false,
            error: "Permission denied",
            error_type: "EACCES",
            error_message: e.message
          }
        end
        logger.warn "Permission denied: #{path}"
        
      rescue StandardError => e
        error_count += 1
        if include_errors
          results << {
            path: path,
            success: false,
            error: "Unexpected error",
            error_type: e.class.name,
            error_message: e.message
          }
        end
        logger.error "Error getting info for #{path}: #{e.class} - #{e.message}"
      end
    end
    
    response = {
      total_requested: paths.length,
      successful: successful_count,
      errors: error_count,
      files: results
    }
    
    JSON.pretty_generate(response)
    
  rescue StandardError => e
    logger.error "Error in bulk file info operation: #{e.message}"
    "Error: #{e.message}"
  end
end

# Framework provides built-in root management tools
# No need to implement list_allowed_directories

# Run the server
begin
  logger.info "Starting MCP server with #{dirs_to_register.size} registered root(s)..."
  server.run
rescue VectorMCP::Error => e
  logger.fatal "VectorMCP Error: #{e.message}"
  exit(1)
rescue Interrupt
  logger.info "Server interrupted."
  exit(0)
rescue StandardError => e
  logger.fatal "Unexpected Server Error: #{e.message}"
  exit(1)
end