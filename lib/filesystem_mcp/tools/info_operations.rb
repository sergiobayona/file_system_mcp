# frozen_string_literal: true

module FileSystemMCP
  module Tools
    class InfoOperations < BaseTool
      def register
        register_get_file_info
        register_get_bulk_file_info
        register_get_server_info
      end

      private

      def register_get_file_info
        @server.register_tool(
          name: "get_file_info",
          description: "Retrieve metadata (size, dates, type, permissions) for a file or directory.",
          input_schema: Schemas::Info::GET_FILE_INFO
        ) do |args|
          handle_file_error do
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
          end
        end
      end

      def register_get_bulk_file_info
        @server.register_tool(
          name: "get_bulk_file_info",
          description: "Retrieve metadata for multiple files or directories in a single operation. More efficient than multiple get_file_info calls.",
          input_schema: Schemas::Info::GET_BULK_FILE_INFO
        ) do |args|
          handle_bulk_file_info(args)
        end
      end

      def handle_bulk_file_info(args)
        paths = args["paths"]
        include_errors = args["include_errors"].nil? ? true : args["include_errors"]
        
        @logger.debug "Getting bulk file info for #{paths.length} paths"
        
        results = []
        successful_count = 0
        error_count = 0
        
        paths.each do |path|
          file_info = get_single_file_info(path, include_errors)
          if file_info[:success]
            successful_count += 1
          else
            error_count += 1
          end
          results << file_info if file_info
        end
        
        response = {
          total_requested: paths.length,
          successful: successful_count,
          errors: error_count,
          files: results.compact
        }
        
        JSON.pretty_generate(response)
      rescue StandardError => e
        @logger.error "Error in bulk file info operation: #{e.message}"
        "Error: #{e.message}"
      end

      def get_single_file_info(path, include_errors)
        stats = File.stat(path)
        
        {
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
      rescue Errno::ENOENT => e
        @logger.warn "File not found: #{path}"
        return nil unless include_errors
        
        {
          path: path,
          success: false,
          error: "File not found",
          error_type: "ENOENT",
          error_message: e.message
        }
      rescue Errno::EACCES => e
        @logger.warn "Permission denied: #{path}"
        return nil unless include_errors
        
        {
          path: path,
          success: false,
          error: "Permission denied",
          error_type: "EACCES",
          error_message: e.message
        }
      rescue StandardError => e
        @logger.error "Error getting info for #{path}: #{e.class} - #{e.message}"
        return nil unless include_errors
        
        {
          path: path,
          success: false,
          error: "Unexpected error",
          error_type: e.class.name,
          error_message: e.message
        }
      end

      def register_get_server_info
        @server.register_tool(
          name: "get_server_info",
          description: "Get server version, runtime information, and configuration details.",
          input_schema: Schemas::Info::GET_SERVER_INFO
        ) do |args|
          handle_server_info
        end
      end

      def handle_server_info
        server_version = "0.5.0"
        
        info = {
          server: {
            name: "VectorMCP::FileSystemServer",
            version: server_version,
            framework: "vector_mcp",
            framework_version: get_vector_mcp_version
          },
          runtime: {
            ruby_version: RUBY_VERSION,
            ruby_platform: RUBY_PLATFORM,
            started_at: Time.now.utc.iso8601(3)
          },
          configuration: {
            authentication_enabled: @server.respond_to?(:authentication_enabled?) ? @server.authentication_enabled? : false,
            registered_roots: get_registered_roots_info
          }
        }

        JSON.pretty_generate(info)
      rescue StandardError => e
        @logger.error "Error getting server info: #{e.message}"
        "Error: #{e.message}"
      end

      def get_registered_roots_info
        if @server.respond_to?(:roots)
          @server.roots.map { |root| root.name }
        else
          ["information_not_available"]
        end
      rescue StandardError
        ["information_not_available"]
      end

      def get_vector_mcp_version
        Gem::Specification.find_by_name('vector_mcp').version.to_s
      rescue Gem::LoadError
        "unknown"
      rescue StandardError
        "unknown"
      end
    end
  end
end