# frozen_string_literal: true

module FileSystemMCP
  module Tools
    class BaseTool
      def initialize(server, logger)
        @server = server
        @logger = logger
      end

      protected

      def handle_file_error(&block)
        yield
      rescue Errno::ENOENT => e
        @logger.error "File not found: #{e.message}"
        "Error: Path not found - #{e.message}"
      rescue Errno::EACCES => e
        @logger.error "Permission denied: #{e.message}"
        "Error: Permission denied - #{e.message}"
      rescue StandardError => e
        @logger.error "Unexpected error: #{e.class} - #{e.message}"
        "Error: An unexpected server error occurred."
      end

      def handle_directory_error(&block)
        yield
      rescue Errno::ENOTDIR => e
        @logger.error "Not a directory: #{e.message}"
        "Error: Expected a directory but found a file - #{e.message}"
      rescue Errno::ENOENT => e
        @logger.error "Directory not found: #{e.message}"
        "Error: Directory not found - #{e.message}"
      rescue Errno::EACCES => e
        @logger.error "Permission denied: #{e.message}"
        "Error: Permission denied - #{e.message}"
      rescue StandardError => e
        @logger.error "Unexpected error: #{e.class} - #{e.message}"
        "Error: An unexpected server error occurred."
      end
    end
  end
end