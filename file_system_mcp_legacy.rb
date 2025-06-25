#!/usr/bin/env ruby
# frozen_string_literal: true

# --- Dependencies ---
require "vector_mcp"
require "pathname"
require "fileutils"
require "diff/lcs"       # For edit_file diffing (gem install diff-lcs)
require "diff/lcs/hunk" # For generating diff output

# --- Configuration & Argument Parsing ---
VectorMCP.logger.level = Logger::INFO # Or Logger::DEBUG for more verbosity

# Helper to expand ~
def expand_home(filepath)
  filepath.start_with?('~') ? File.expand_path(filepath) : filepath
end

# Helper to normalize paths consistently
def normalize_path(p)
  Pathname.new(p).cleanpath.to_s
end

# Get allowed directories from command line arguments
args = ARGV
if args.empty?
  warn "Usage: #{$PROGRAM_NAME} <allowed-directory-1> [allowed-directory-2 ...]"
  warn "Example: #{$PROGRAM_NAME} ~/projects /var/data"
  exit(1)
end

ALLOWED_DIRECTORIES = args.map do |dir|
  begin
    expanded = expand_home(dir)
    pathname = Pathname.new(expanded).expand_path
    unless pathname.directory?
      warn "Error: Argument '#{dir}' is not a valid directory or cannot be accessed."
      exit(1)
    end
    # Store the normalized, absolute path string
    normalize_path(pathname.realpath.to_s) # Use realpath to resolve symlinks for the base allowed dir
  rescue Errno::ENOENT
    warn "Error: Argument directory '#{dir}' does not exist."
    exit(1)
  rescue StandardError => e
    warn "Error processing argument directory '#{dir}': #{e.message}"
    exit(1)
  end
end.uniq

VectorMCP.logger.info "MCP Filesystem Server starting."
VectorMCP.logger.info "Allowed directories: #{ALLOWED_DIRECTORIES.join(', ')}"

# --- Security ---

# Custom error for path validation failures
class PathSecurityError < StandardError; end

# Validates that a requested path falls within the allowed directories.
# Handles symlinks. For non-existent paths, checks the parent.
# Returns the validated, absolute, real path string if it exists,
# or the validated, absolute path string if it doesn't exist but its parent is allowed.
# Raises PathSecurityError if validation fails.
def validate_path(requested_path)
  # 1. Expand home dir and make absolute relative to CWD if needed
  absolute_path = Pathname.new(expand_home(requested_path)).expand_path
  normalized_requested = normalize_path(absolute_path.to_s)

  # 2. Check if the *requested* path (normalized) starts within an allowed dir *initially*
  # This prevents trivial cases like "../../../etc/passwd" if CWD is allowed
  is_initially_allowed = ALLOWED_DIRECTORIES.any? { |allowed_dir| normalized_requested.start_with?(allowed_dir + File::SEPARATOR) || normalized_requested == allowed_dir }
  unless is_initially_allowed
    raise PathSecurityError, "Access denied: Path '#{requested_path}' resolves outside allowed directories."
  end

  # 3. Handle existing paths vs non-existent paths (e.g., for writing)
  if absolute_path.exist?
    begin
      # Resolve symlinks fully for existing paths
      real_path = absolute_path.realpath
      normalized_real = normalize_path(real_path.to_s)

      # Check if the *real* path is within allowed directories
      is_real_path_allowed = ALLOWED_DIRECTORIES.any? { |allowed_dir| normalized_real.start_with?(allowed_dir + File::SEPARATOR) || normalized_real == allowed_dir }
      unless is_real_path_allowed
        raise PathSecurityError, "Access denied: Path '#{requested_path}' resolves via symlinks outside allowed directories."
      end
      normalized_real # Return the normalized real path string
    rescue Errno::EACCES => e
      raise PathSecurityError, "Permission denied while accessing '#{requested_path}': #{e.message}"
    rescue Errno::ENOENT
      # This might happen in a race condition if file deleted between check and realpath
      raise PathSecurityError, "Path '#{requested_path}' disappeared during validation."
    end
  else
    # For non-existent paths (e.g., write_file, create_directory), check the *parent* directory
    parent_dir = absolute_path.parent
    begin
      # Parent MUST exist
      real_parent_path = parent_dir.realpath
      normalized_parent = normalize_path(real_parent_path.to_s)

      # Check if the parent's real path is within allowed directories
      is_parent_allowed = ALLOWED_DIRECTORIES.any? { |allowed_dir| normalized_parent.start_with?(allowed_dir + File::SEPARATOR) || normalized_parent == allowed_dir }
      unless is_parent_allowed
        raise PathSecurityError, "Access denied: Cannot create '#{requested_path}'. Parent directory resolves outside allowed directories."
      end
      normalized_requested # Return the normalized *requested* path string (since it doesn't exist yet)
    rescue Errno::ENOENT
      raise PathSecurityError, "Access denied: Cannot create '#{requested_path}'. Parent directory does not exist."
    rescue Errno::EACCES => e
      raise PathSecurityError, "Permission denied while accessing parent of '#{requested_path}': #{e.message}"
    end
  end
end

# --- Diff Formatting Helper ---
def create_unified_diff(old_content, new_content, file_path)
  old_lines = old_content.lines
  new_lines = new_content.lines
  diffs = Diff::LCS.sdiff(old_lines, new_lines)

  output = []
  output << "--- a/#{file_path}"
  output << "+++ b/#{file_path}"

  # Use Diff::LCS::Hunk to generate hunks in unified format
  # Note: context_lines=3 is standard for unified diff
  hunk_generator = Diff::LCS::Hunk.new(old_lines, new_lines, diffs, 3, 0)

  return "No changes detected.\n" if hunk_generator.empty?

  hunk_generator.each_hunk do |hunk|
    output << hunk.diff(:unified)
  end

  # Add newline at the end if the last line wasn't a newline char itself
  # (Standard diff format often expects this)
  result = output.join
  result += "\n" unless result.end_with?("\n")
  result
end

# --- Server Setup ---
server = VectorMCP.new(name: "VectorMCP::FileSystemServer", version: "0.3.0")

# --- Tool Schemas (as Hashes) ---
SCHEMA_PATH_ARG = { type: "object", properties: { path: { type: "string" } }, required: ["path"] }
SCHEMA_WRITE_ARGS = { type: "object", properties: { path: { type: "string" }, content: { type: "string" } }, required: ["path", "content"] }
SCHEMA_EDIT_OPERATION = {
  type: "object",
  properties: {
    oldText: { type: "string", description: "Text to search for - must match exactly" },
    newText: { type: "string", description: "Text to replace with" }
  },
  required: ["oldText", "newText"]
}
SCHEMA_EDIT_ARGS = {
  type: "object",
  properties: {
    path: { type: "string" },
    edits: { type: "array", items: SCHEMA_EDIT_OPERATION },
    dryRun: { type: "boolean", description: "Preview changes using git-style diff format", default: false }
  },
  required: ["path", "edits"]
}
SCHEMA_MOVE_ARGS = { type: "object", properties: { source: { type: "string" }, destination: { type: "string" } }, required: ["source", "destination"] }
SCHEMA_SEARCH_ARGS = {
  type: "object",
  properties: {
    path: { type: "string" },
    pattern: { type: "string", description: "Glob pattern (e.g., '*.txt', 'data/**/log?.log')" },
    excludePatterns: { type: "array", items: { type: "string" }, default: [], description: "Glob patterns to exclude" }
  },
  required: ["path", "pattern"]
}
SCHEMA_READ_MULTI_ARGS = { type: "object", properties: { paths: { type: "array", items: { type: "string" } } }, required: ["paths"] }
SCHEMA_EMPTY_ARGS = { type: "object", properties: {}, required: [] }

# --- Tool Implementations ---

# Helper for tool handlers to catch common errors
def handle_tool_errors
  begin
    yield
  rescue PathSecurityError => e
    VectorMCP.logger.warn "PathSecurityError in tool: #{e.message}"
    "Security Error: #{e.message}"
  rescue Errno::ENOENT => e
    VectorMCP.logger.error "File Not Found Error in tool: #{e.message}"
    "Error: Path not found - #{e.message}"
  rescue Errno::EACCES => e
    VectorMCP.logger.error "Permission Error in tool: #{e.message}"
    "Error: Permission denied - #{e.message}"
  rescue Errno::EISDIR => e
    VectorMCP.logger.error "Is Directory Error in tool: #{e.message}"
    "Error: Expected a file but found a directory - #{e.message}"
  rescue Errno::ENOTDIR => e
    VectorMCP.logger.error "Not Directory Error in tool: #{e.message}"
    "Error: Expected a directory but found a file - #{e.message}"
  rescue StandardError => e
    VectorMCP.logger.error "Unexpected Error in tool: #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    "Error: An unexpected server error occurred."
  end
end

server.register_tool(
  name: "read_file",
  description: "Read the complete contents of a single file. Only works within allowed directories.",
  input_schema: SCHEMA_PATH_ARG
) do |args, _session|
  handle_tool_errors do
    valid_path = validate_path(args["path"])
    VectorMCP.logger.debug { "Reading file: #{valid_path}" }
    File.read(valid_path)
  end
end

server.register_tool(
  name: "read_multiple_files",
  description: "Read the contents of multiple files. Returns content prefixed by path, or an error message per file. Only works within allowed directories.",
  input_schema: SCHEMA_READ_MULTI_ARGS
) do |args, _session|
  results = args["paths"].map do |p|
    handle_tool_errors do
      valid_path = validate_path(p)
      VectorMCP.logger.debug { "Reading multiple file: #{valid_path}" }
      content = File.read(valid_path)
      "#{p}:\n#{content}\n" # Use original path 'p' for user reference
    end
  end
  # Join results, handling potential error strings from handle_tool_errors
  results.join("\n---\n")
end

server.register_tool(
  name: "write_file",
  description: "Create a new file or overwrite an existing file with content. Use with caution. Only works within allowed directories.",
  input_schema: SCHEMA_WRITE_ARGS
) do |args, _session|
  handle_tool_errors do
    valid_path = validate_path(args["path"]) # Validates parent dir is allowed if file doesn't exist
    content = args["content"]
    VectorMCP.logger.debug { "Writing file: #{valid_path}" }
    File.write(valid_path, content)
    "Successfully wrote to #{args["path"]}" # Use original path for user feedback
  end
end

server.register_tool(
  name: "edit_file",
  description: "Make exact text replacements in a file. Use dryRun=true to preview changes as a unified diff. Only works within allowed directories.",
  input_schema: SCHEMA_EDIT_ARGS
) do |args, _session|
  handle_tool_errors do
    file_path_arg = args["path"]
    valid_path = validate_path(file_path_arg)
    edits = args["edits"]
    dry_run = args["dryRun"] || false # Handle nil case

    VectorMCP.logger.debug { "Editing file: #{valid_path} (dryRun: #{dry_run})" }

    original_content = File.read(valid_path)
    modified_content = original_content.dup # Work on a copy

    edits.each do |edit|
      old_text = edit["oldText"]
      new_text = edit["newText"]
      unless modified_content.gsub!(old_text, new_text)
        # If simple gsub fails, maybe indicate the specific failure?
        # For now, we'll let it proceed, the diff will show no change for this edit.
        VectorMCP.logger.warn "Edit failed: Text not found in #{valid_path}: #{old_text.inspect}"
        # Could raise here, but TS example implies it continues? Returning diff is safer.
        # raise ArgumentError, "Edit failed: Text not found: #{old_text.inspect}"
      end
    end

    diff_output = create_unified_diff(original_content, modified_content, file_path_arg)

    unless dry_run
      if original_content != modified_content
        File.write(valid_path, modified_content)
        VectorMCP.logger.info "Applied edits to #{valid_path}"
      else
        VectorMCP.logger.info "No actual changes made to #{valid_path} after edits."
      end
    end

    # Return the diff
    "`".ljust(3, "`") + "diff\n" + diff_output + "`".ljust(3, "`") + "\n\n" +
      (dry_run ? "Dry run complete. No changes were written." : "Edits applied successfully.")

  end
end

server.register_tool(
  name: "create_directory",
  description: "Create a directory, including parent directories if needed. Only works within allowed directories.",
  input_schema: SCHEMA_PATH_ARG
) do |args, _session|
  handle_tool_errors do
    valid_path = validate_path(args["path"]) # Validates parent dir is allowed
    VectorMCP.logger.debug { "Creating directory: #{valid_path}" }
    FileUtils.mkdir_p(valid_path)
    "Successfully created directory #{args["path"]}"
  end
end

server.register_tool(
  name: "list_directory",
  description: "List files and directories in a path as a JSON array with each item containing \"name\" and \"type\" (\"file\" or \"directory\"). Only works within allowed directories.",
  input_schema: SCHEMA_PATH_ARG
) do |args, _session|
  handle_tool_errors do
    valid_path = validate_path(args["path"])
    unless Pathname.new(valid_path).directory? # Ensure it *is* a directory after validation
       raise Errno::ENOTDIR, valid_path
    end

    VectorMCP.logger.debug { "Listing directory: #{valid_path}" }
    require 'json'

    # Build structured data instead of a human string so that
    # filenames containing visually-confusing Unicode characters
    # can be copied exactly as-is by clients.
    entries = Dir.children(valid_path).map do |entry_name|
      entry_path = File.join(valid_path, entry_name)
      type = begin
                File.directory?(entry_path) ? 'directory' : 'file'
              rescue Errno::ENOENT, Errno::EACCES
                'error' # Could not stat; still return the name so user sees it
              end
      { type: type, name: entry_name }
    end.sort_by { |e| [e[:type], e[:name].downcase] }

    JSON.pretty_generate(entries)
  end
end

server.register_tool(
  name: "directory_tree",
  description: "Get a recursive tree view of files and directories as a JSON structure. Only works within allowed directories.",
  input_schema: SCHEMA_PATH_ARG
) do |args, _session|
  handle_tool_errors do
    root_path_str = validate_path(args["path"])
    root_path = Pathname.new(root_path_str)
    unless root_path.directory?
       raise Errno::ENOTDIR, root_path_str
    end

    VectorMCP.logger.debug { "Building directory tree for: #{root_path_str}" }

    build_tree = lambda do |current_path|
      entries = []
      begin
        Dir.children(current_path.to_s).sort.each do |name|
          child_path = current_path.join(name)
          # Validate every child path before adding to tree
          begin
             validate_path(child_path.to_s) # Check if accessible
          rescue PathSecurityError, Errno::EACCES, Errno::ENOENT
             next # Skip inaccessible or disappearing files/dirs
          end

          entry_data = { name: name }
          if child_path.directory?
            entry_data[:type] = 'directory'
            entry_data[:children] = build_tree.call(child_path)
          else
            entry_data[:type] = 'file'
            # Files don't have a children key per the description
          end
          entries << entry_data
        end
      rescue Errno::EACCES
        # Cannot read directory, return empty children but log
        VectorMCP.logger.warn "Permission denied reading directory: #{current_path}"
      rescue Errno::ENOENT
        # Directory disappeared?
        VectorMCP.logger.warn "Directory not found during tree build: #{current_path}"
      end
      entries
    end

    tree_data = build_tree.call(root_path)

    require 'json' # Ensure JSON is required
    # Return JSON string directly
    JSON.pretty_generate({ name: root_path.basename.to_s, type: 'directory', children: tree_data })
  end
end


server.register_tool(
  name: "move_file",
  description: "Move or rename a file or directory. Fails if the destination exists. Both source and destination must be within allowed directories.",
  input_schema: SCHEMA_MOVE_ARGS
) do |args, _session|
  handle_tool_errors do
    source_arg = args["source"]
    dest_arg = args["destination"]

    # Validate source exists and is allowed
    valid_source = validate_path(source_arg)
    # Validate destination's *parent* is allowed, and destination itself doesn't exist yet
    valid_dest = validate_path(dest_arg) # This validates parent if dest doesn't exist

    if Pathname.new(valid_dest).exist?
      raise Errno::EEXIST, "Destination path '#{dest_arg}' already exists."
    end

    VectorMCP.logger.debug { "Moving: #{valid_source} -> #{valid_dest}" }
    FileUtils.mv(valid_source, valid_dest)
    "Successfully moved #{source_arg} to #{dest_arg}"
  end
end

server.register_tool(
  name: "search_files",
  description: "Recursively search for files/directories matching a glob pattern within allowed directories. Case-insensitive matching on basename.",
  input_schema: SCHEMA_SEARCH_ARGS
) do |args, _session|
  handle_tool_errors do
    root_path_str = validate_path(args["path"])
    root_path = Pathname.new(root_path_str)
    pattern = args["pattern"]
    exclude_patterns = args["excludePatterns"] || []

    unless root_path.directory?
       raise Errno::ENOTDIR, root_path_str
    end

    VectorMCP.logger.debug { "Searching under #{root_path_str} for pattern '#{pattern}', excluding #{exclude_patterns}" }

    results = []
    # Pathname#find recursively yields Pathname objects
    root_path.find do |pathname|
      # Validate every path found *before* checking patterns
      begin
        validated_pathname_str = validate_path(pathname.to_s)
        # Check against exclude patterns first (relative path)
        relative_path = pathname.relative_path_from(root_path).to_s
        is_excluded = exclude_patterns.any? do |exclude_pattern|
          # File.fnmatch provides shell globbing (FNM_PATHNAME allows matching across dirs, FNM_DOTMATCH includes dotfiles)
          File.fnmatch(exclude_pattern, relative_path, File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_CASEFOLD) ||
          File.fnmatch(exclude_pattern, pathname.basename.to_s, File::FNM_DOTMATCH | File::FNM_CASEFOLD) # Also check basename only
        end
        next if is_excluded

        # Check against the main search pattern (basename matching, case-insensitive)
        # Use FNM_CASEFOLD for case-insensitivity
        if File.fnmatch(pattern, pathname.basename.to_s, File::FNM_DOTMATCH | File::FNM_CASEFOLD)
          results << validated_pathname_str # Add the validated path string
        end

      rescue PathSecurityError, Errno::EACCES, Errno::ENOENT
        # Skip paths we can't validate or access
        Find.prune if pathname.directory? # Don't descend into inaccessible directories
        next
      end
    end

    results.empty? ? "No matches found" : results.join("\n")
  end
end

server.register_tool(
  name: "get_file_info",
  description: "Retrieve metadata (size, dates, type, permissions) for a file or directory. Only works within allowed directories.",
  input_schema: SCHEMA_PATH_ARG
) do |args, _session|
  handle_tool_errors do
    valid_path = validate_path(args["path"])
    stats = File.stat(valid_path)
    info = {
      path: args["path"], # User-friendly original path
      absolute_path: valid_path,
      size: stats.size,
      created: stats.birthtime,
      modified: stats.mtime,
      accessed: stats.atime,
      isDirectory: stats.directory?,
      isFile: stats.file?,
      isSymlink: stats.symlink?, # Might be useful
      permissions: format("%o", stats.mode & 0o777), # Format permissions as octal string
      uid: stats.uid,
      gid: stats.gid
    }
    # Format into key: value lines
    info.map { |k, v| "#{k}: #{v}" }.join("\n")
  end
end

server.register_tool(
  name: "list_allowed_directories",
  description: "List the base directories the server is configured to access.",
  input_schema: SCHEMA_EMPTY_ARGS
) do |_args, _session|
  # No error handling needed here as it uses pre-validated config
  VectorMCP.logger.debug "Listing allowed directories"
  "Allowed directories:\n#{ALLOWED_DIRECTORIES.join("\n")}"
end

# --- Run the Server ---
begin
  server.run # Uses stdio transport by default
rescue VectorMCP::Error => e
  VectorMCP.logger.fatal("VectorMCP Error: #{e.message}")
  exit(1)
rescue Interrupt
  VectorMCP.logger.info("Server interrupted.")
  exit(0)
rescue StandardError => e
  VectorMCP.logger.fatal("Unexpected Server Error: #{e.message}\n#{e.backtrace.join("\n")}")
  exit(1)
end
