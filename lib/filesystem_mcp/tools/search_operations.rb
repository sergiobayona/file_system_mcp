# frozen_string_literal: true

module FileSystemMCP
  module Tools
    class SearchOperations < BaseTool
      def register
        register_search_files
        register_find_files
      end

      private

      def register_search_files
        @server.register_tool(
          name: "search_files",
          description: "Recursively search for files/directories matching a glob pattern.",
          input_schema: Schemas::Search::SEARCH_FILES
        ) do |args|
          handle_directory_error do
            root_path = Pathname.new(args["path"])
            pattern = args["pattern"]
            exclude_patterns = args["excludePatterns"] || []
            
            unless root_path.directory?
              raise Errno::ENOTDIR, args["path"]
            end
            
            @logger.debug "Searching under #{args['path']} for pattern '#{pattern}'"
            
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
          end
        end
      end

      def register_find_files
        @server.register_tool(
          name: "find_files",
          description: "Advanced file finder with sorting, filtering, and metadata. Recursively searches directories with powerful filtering options.",
          input_schema: Schemas::Search::FIND_FILES
        ) do |args|
          handle_directory_error do
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
            
            @logger.debug "Finding files under #{args['path']} (sort: #{sort_by} #{order}, limit: #{limit})"
            
            results = find_and_filter_files(root_path, {
              file_types: file_types,
              modified_after: modified_after,
              modified_before: modified_before,
              min_size: min_size,
              max_size: max_size,
              include_directories: include_directories
            })
            
            # Sort results
            sort_results!(results, sort_by, order)
            
            # Apply limit
            results = results.first(limit) if limit
            
            # Format output
            format_find_results(results)
          end
        rescue ArgumentError => e
          @logger.error "Invalid parameter: #{e.message}"
          "Error: Invalid parameter - #{e.message}"
        end
      end

      def find_and_filter_files(root_path, filters)
        results = []
        
        root_path.find do |pathname|
          begin
            next if pathname == root_path # Skip the root directory itself
            
            is_directory = pathname.directory?
            
            # Skip directories if not requested
            next if is_directory && !filters[:include_directories]
            
            # Get file stats
            stats = pathname.stat
            
            # Apply file type filter (only for files)
            if !is_directory && filters[:file_types]
              ext = pathname.extname.downcase.sub(/^\./, '')
              next unless filters[:file_types].include?(ext)
            end
            
            # Apply date filters
            next if filters[:modified_after] && stats.mtime < filters[:modified_after]
            next if filters[:modified_before] && stats.mtime > filters[:modified_before]
            
            # Apply size filters (only for files)
            if !is_directory
              next if filters[:min_size] && stats.size < filters[:min_size]
              next if filters[:max_size] && stats.size > filters[:max_size]
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
            @logger.warn "Cannot access #{pathname}: #{e.message}"
            Find.prune if pathname.directory?
            next
          end
        end
        
        results
      end

      def sort_results!(results, sort_by, order)
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
      end

      def format_find_results(results)
        if results.empty?
          "No files found matching the criteria"
        else
          JSON.pretty_generate({
            total_found: results.length,
            files: results
          })
        end
      end
    end
  end
end