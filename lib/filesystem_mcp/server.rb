# frozen_string_literal: true

module FileSystemMCP
  class Server
    def initialize(config)
      @config = config

      # Initialize server with browser navigation support
      server_options = {
        name: "VectorMCP::FileSystemServer",
        version: "0.5.0",
        transport: :sse,  # Enable Server-Sent Events for browser navigation
        host: "localhost",
        port: 8080,
        path_prefix: "/fs"
      }

      @server = VectorMCP.new(**server_options)
      @logger = VectorMCP.logger
    end

    def setup
      log_startup_info
      register_roots
      setup_security if @config.enable_auth
      register_tools
      self
    end

    def run
      @logger.info "Starting MCP server with #{@config.dirs_to_register.size} registered root(s)..."
      @logger.info "Browser navigation available at: http://localhost:8080/fs/sse"
      @server.run
    rescue VectorMCP::Error => e
      @logger.fatal "VectorMCP Error: #{e.message}"
      exit(1)
    rescue Interrupt
      @logger.info "Server interrupted."
      exit(0)
    rescue StandardError => e
      @logger.fatal "Unexpected Server Error: #{e.message}"
      exit(1)
    end

    private

    def log_startup_info
      mode = @config.enable_auth ? "Secure Mode, " : ""
      @logger.info "MCP Filesystem Server (#{mode}Roots-based) starting"
      @logger.info "Authentication: #{@config.enable_auth ? 'Enabled' : 'Disabled'}" if @config.respond_to?(:enable_auth)
      @logger.info "Registering roots for: #{@config.dirs_to_register.map { |d| d[:original] }.join(', ')}"
    end

    def register_roots
      @config.dirs_to_register.each do |dir_info|
        begin
          @server.register_root_from_path(dir_info[:expanded], name: dir_info[:name])
          @logger.info "Registered root '#{dir_info[:name]}' for #{dir_info[:original]}"
        rescue StandardError => e
          @logger.error "Failed to register root for #{dir_info[:original]}: #{e.message}"
          exit(1)
        end
      end
    end

    def setup_security
      @server.enable_authentication!(
        strategy: :api_key,
        keys: [@config.api_key]
      )
      configure_authorization
      @logger.info "Security policies configured"
    end

    def configure_authorization
      @server.authorize_tools do |user, action, tool|
        # Simple authorization: all authenticated users can access all tools
        !user.nil?
      end
    end

    def register_tools
      [
        Tools::FileOperations,
        Tools::DirectoryOperations,
        Tools::SearchOperations,
        Tools::InfoOperations
      ].each { |tool_class| tool_class.new(@server, @logger).register }
    end
  end
end
