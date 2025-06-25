#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/filesystem_mcp'

# Parse configuration (supports --enable-auth flag) and initialize server
config = FileSystemMCP::Config.new(ARGV)
server = FileSystemMCP::Server.new(config)

# Setup and run the server (with optional security if --enable-auth was passed)
server.setup.run