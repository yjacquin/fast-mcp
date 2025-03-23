# frozen_string_literal: true

# Fast MCP - A Ruby Implementation of the Model Context Protocol (Server-side)
# https://modelcontextprotocol.io/introduction

# Define the MCP module
module MCP
end

# Require the core components
require_relative 'mcp/tool'
require_relative 'mcp/server'
require_relative 'mcp/resource'

# Require all transport files
require_relative 'mcp/transports/base_transport'
Dir[File.join(File.dirname(__FILE__), 'mcp/transports', '*.rb')].each do |file|
  require file
end

# Version information
require_relative 'mcp/version'

# Convenience method to create a Rack middleware
module MCP
  # Create a Rack middleware for the MCP server
  # @param app [#call] The Rack application
  # @param options [Hash] Options for the middleware
  # @option options [String] :name The name of the server
  # @option options [String] :version The version of the server
  # @option options [String] :path_prefix The path prefix for the MCP endpoints
  # @option options [Logger] :logger The logger to use
  # @yield [server] A block to configure the server
  # @yieldparam server [MCP::Server] The server to configure
  # @return [#call] The Rack middleware
  def self.rack_middleware(app, options = {})
    name = options.delete(:name) || 'mcp-server'
    version = options.delete(:version) || '1.0.0'
    logger = options.delete(:logger) || Logger.new

    server = MCP::Server.new(name: name, version: version, logger: logger)
    yield server if block_given?

    # Store the server in the Sinatra settings if available
    app.settings.set(:mcp_server, server) if app.respond_to?(:settings) && app.settings.respond_to?(:mcp_server=)

    server.start_rack(app, options)
  end

  # Create a Rack middleware for the MCP server with authentication
  # @param app [#call] The Rack application
  # @param options [Hash] Options for the middleware
  # @option options [String] :name The name of the server
  # @option options [String] :version The version of the server
  # @option options [String] :auth_token The authentication token
  # @yield [server] A block to configure the server
  # @yieldparam server [MCP::Server] The server to configure
  # @return [#call] The Rack middleware
  def self.authenticated_rack_middleware(app, options = {})
    name = options.delete(:name) || 'mcp-server'
    version = options.delete(:version) || '1.0.0'
    logger = options.delete(:logger) || Logger.new

    server = MCP::Server.new(name: name, version: version, logger: logger)
    yield server if block_given?

    server.start_authenticated_rack(app, options)
  end
end
