# frozen_string_literal: true

require 'rack'
require 'logger'
require 'mcp/server'
require 'mcp/transports/rack_transport'

module FastMcp
  # Rack middleware for integrating MCP with Rails
  class RackMiddleware
    # Initialize the middleware
    # @param app [#call] The Rack application
    # @param options [Hash] Options for the middleware
    # @option options [String] :name The name of the server
    # @option options [String] :version The version of the server
    # @option options [String] :path_prefix The path prefix for the MCP endpoints
    # @option options [Logger] :logger The logger to use
    # @yield [server] A block to configure the server
    # @yieldparam server [FastMcp::Server] The MCP server instance
    class << self
      def server
        Server.new(name: @name, version: @version, logger: @logger)
      end
    end

    def initialize(app, options = {}, &block)
      @app = app
      @name = options[:name] || 'mcp-server'
      @version = options[:version] || '1.0.0'
      @path_prefix = options[:path_prefix] || '/mcp'

      # Ensure we have a valid logger
      @logger = options[:logger] || Logger.new($stdout)

      @server = server

      # Configure the server with the provided block
      yield @server if block_given?

      # Create and start the transport
      @transport = Transports::RackTransport.new(
        @server,
        @app,
        { path_prefix: @path_prefix, logger: @logger }.merge(options)
      )
      @transport.start
    end

    # Process the request
    # @param env [Hash] The Rack environment
    # @return [Array] The Rack response
    def call(env)
      @transport.call(env)
    end
  end
end
