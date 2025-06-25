# frozen_string_literal: true

module FileSystemMCP
  class Config
    attr_reader :dirs_to_register, :enable_auth, :api_key

    def initialize(args)
      parse_arguments(args)
      validate_directories
    end

    private

    def parse_arguments(args)
      @args = args.dup
      @enable_auth = @args.delete("--enable-auth")
      @api_key = nil

      if @enable_auth
        @api_key = ENV["FILESYSTEM_MCP_API_KEY"]
        if @api_key.nil? || @api_key.empty?
          warn "Error: --enable-auth requires FILESYSTEM_MCP_API_KEY environment variable"
          exit(1)
        end
      end

      if @args.empty?
        warn "Usage: #{$PROGRAM_NAME} [--enable-auth] <allowed-directory-1> [allowed-directory-2 ...]"
        warn "Example: #{$PROGRAM_NAME} ~/projects /var/data"
        warn "         FILESYSTEM_MCP_API_KEY=secret #{$PROGRAM_NAME} --enable-auth ~/projects"
        exit(1)
      end
    end

    def validate_directories
      @dirs_to_register = @args.map.with_index do |dir, index|
        expanded = expand_home(dir)
        { original: dir, expanded: expanded, name: "#{File.basename(expanded)}_#{index}" }
      end
    end

    def expand_home(filepath)
      filepath.start_with?('~') ? File.expand_path(filepath) : filepath
    end
  end
end