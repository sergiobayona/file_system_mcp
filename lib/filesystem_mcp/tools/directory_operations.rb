# frozen_string_literal: true

module FileSystemMCP
  module Tools
    class DirectoryOperations < BaseTool
      def register
        register_list_directory
        register_create_directory
      end

      private

      def register_list_directory
        @server.register_tool(
          name: "list_directory",
          description: "List files and directories in a path as a JSON array.",
          input_schema: Schemas::Directory::LIST_DIRECTORY
        ) do |args|
          handle_directory_error do
            unless Pathname.new(args["path"]).directory?
              raise Errno::ENOTDIR, args["path"]
            end
            
            include_metadata = args["include_metadata"] || false
            @logger.debug "Listing directory: #{args['path']} (metadata: #{include_metadata})"
            
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
                    @logger.warn "Could not get metadata for #{entry_path}: #{e.message}"
                    # Continue without metadata for this entry
                  end
                end
                
                entry
              rescue Errno::ENOENT, Errno::EACCES
                { type: 'error', name: entry_name }
              end
            end.sort_by { |e| [e[:type], e[:name].downcase] }
            
            JSON.pretty_generate(entries)
          end
        end
      end

      def register_create_directory
        @server.register_tool(
          name: "create_directory",
          description: "Create a directory, including parent directories if needed.",
          input_schema: Schemas::Directory::CREATE_DIRECTORY
        ) do |args|
          handle_directory_error do
            @logger.debug "Creating directory: #{args['path']}"
            FileUtils.mkdir_p(args["path"])
            "Successfully created directory #{args["path"]}"
          end
        end
      end
    end
  end
end