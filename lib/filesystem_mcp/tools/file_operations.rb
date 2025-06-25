# frozen_string_literal: true

module FileSystemMCP
  module Tools
    class FileOperations < BaseTool
      include FileSystemMCP::Utils::DiffUtils

      def register
        register_read_file
        register_read_multiple_files
        register_write_file
        register_edit_file
        register_move_file
      end

      private

      def register_read_file
        @server.register_tool(
          name: "read_file",
          description: "Read the complete contents of a single file. Only works within registered roots.",
          input_schema: Schemas::File::READ_FILE
        ) do |args|
          handle_file_error do
            @logger.debug "Reading file: #{args['path']}"
            File.read(args["path"])
          end
        end
      end

      def register_read_multiple_files
        @server.register_tool(
          name: "read_multiple_files",
          description: "Read the contents of multiple files. Returns content prefixed by path, or an error message per file.",
          input_schema: Schemas::File::READ_MULTIPLE_FILES
        ) do |args|
          results = args["paths"].map do |path|
            begin
              @logger.debug "Reading multiple file: #{path}"
              content = File.read(path)
              "#{path}:\n#{content}\n"
            rescue StandardError => e
              @logger.error "Error reading #{path}: #{e.message}"
              "#{path}: Error: #{e.message}"
            end
          end
          results.join("\n---\n")
        end
      end

      def register_write_file
        @server.register_tool(
          name: "write_file",
          description: "Create a new file or overwrite an existing file with content. Use with caution.",
          input_schema: Schemas::File::WRITE_FILE
        ) do |args|
          handle_file_error do
            @logger.debug "Writing file: #{args['path']}"
            File.write(args["path"], args["content"])
            "Successfully wrote to #{args["path"]}"
          end
        end
      end

      def register_edit_file
        @server.register_tool(
          name: "edit_file",
          description: "Make exact text replacements in a file. Use dryRun=true to preview changes.",
          input_schema: Schemas::File::EDIT_FILE
        ) do |args|
          handle_file_error do
            edits = args["edits"]
            dry_run = args["dryRun"] || false
            
            @logger.debug "Editing file: #{args['path']} (dryRun: #{dry_run})"
            
            original_content = File.read(args["path"])
            modified_content = original_content.dup
            
            edits.each do |edit|
              old_text = edit["oldText"]
              new_text = edit["newText"]
              unless modified_content.gsub!(old_text, new_text)
                @logger.warn "Edit failed: Text not found in #{args['path']}: #{old_text.inspect}"
              end
            end
            
            diff_output = create_unified_diff(original_content, modified_content, args["path"])
            
            unless dry_run
              if original_content != modified_content
                File.write(args["path"], modified_content)
                @logger.info "Applied edits to #{args['path']}"
              else
                @logger.info "No actual changes made to #{args['path']}"
              end
            end
            
            "```diff\n#{diff_output}```\n\n#{dry_run ? 'Dry run complete. No changes were written.' : 'Edits applied successfully.'}"
          end
        end
      end

      def register_move_file
        @server.register_tool(
          name: "move_file",
          description: "Move or rename a file or directory. Fails if the destination exists.",
          input_schema: Schemas::File::MOVE_FILE
        ) do |args|
          handle_file_error do
            if Pathname.new(args["destination"]).exist?
              raise Errno::EEXIST, "Destination path '#{args["destination"]}' already exists."
            end
            
            @logger.debug "Moving: #{args['source']} -> #{args['destination']}"
            FileUtils.mv(args["source"], args["destination"])
            "Successfully moved #{args["source"]} to #{args["destination"]}"
          end
        end
      end
    end
  end
end