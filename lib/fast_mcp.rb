# frozen_string_literal: true

# Fast MCP - A Ruby Implementation of the Model Context Protocol (Server-side)
# https://modelcontextprotocol.io/introduction

# Define the MCP module
module FastMcp
  class << self
    attr_accessor :server
  end
end

# Require the core components
require_relative 'mcp/tool'
require_relative 'mcp/server'
require_relative 'mcp/resource'
require_relative 'mcp/railtie' if defined?(Rails::Railtie)

# Load generators if Rails is available
require_relative 'generators/fast_mcp/install/install_generator' if defined?(Rails::Generators)

# Require all transport files
require_relative 'mcp/transports/base_transport'
Dir[File.join(File.dirname(__FILE__), 'mcp/transports', '*.rb')].each do |file|
  require file
end

# Require OAuth resource server components
require_relative 'mcp/oauth/token_validator'
require_relative 'mcp/oauth/introspection'
require_relative 'mcp/oauth/resource_server'

# Version information
require_relative 'mcp/version'

# Convenience method to create a Rack middleware
module FastMcp
  # Create a Rack middleware for the MCP server
  # @param app [#call] The Rack application
  # @param options [Hash] Options for the middleware
  # @option options [String] :name The name of the server
  # @option options [String] :version The version of the server
  # @option options [String] :path_prefix The path prefix for the MCP endpoints
  # @option options [String] :messages_route The route for the messages endpoint
  # @option options [String] :sse_route The route for the SSE endpoint
  # @option options [Logger] :logger The logger to use
  # @option options [Array<String,Regexp>] :allowed_origins List of allowed origins for DNS rebinding protection
  # @yield [server] A block to configure the server
  # @yieldparam server [FastMcp::Server] The server to configure
  # @return [#call] The Rack middleware
  def self.rack_middleware(app, options = {}, &block)
    name = options.delete(:name) || 'mcp-server'
    version = options.delete(:version) || '1.0.0'
    logger = options.delete(:logger) || Logger.new

    server = FastMcp::Server.new(name: name, version: version, logger: logger)
    yield server if block_given?

    # Store the server in the Sinatra settings if available
    app.settings.set(:mcp_server, server) if app.respond_to?(:settings) && app.settings.respond_to?(:mcp_server=)

    # Store the server in the FastMcp module
    self.server = server

    server.start_rack(app, options)
  end

  # Create a Rack middleware for the MCP server with authentication
  # @param app [#call] The Rack application
  # @param options [Hash] Options for the middleware
  # @option options [String] :name The name of the server
  # @option options [String] :version The version of the server
  # @option options [String] :auth_token The authentication token
  # @option options [Array<String,Regexp>] :allowed_origins List of allowed origins for DNS rebinding protection
  # @yield [server] A block to configure the server
  # @yieldparam server [FastMcp::Server] The server to configure
  # @return [#call] The Rack middleware
  def self.authenticated_rack_middleware(app, options = {}, &block)
    name = options.delete(:name) || 'mcp-server'
    version = options.delete(:version) || '1.0.0'
    logger = options.delete(:logger) || Logger.new

    server = FastMcp::Server.new(name: name, version: version, logger: logger)
    yield server if block_given?

    # Store the server in the FastMcp module
    self.server = server

    server.start_authenticated_rack(app, options)
  end

  # Register a tool with the MCP server
  # @param tool [FastMcp::Tool] The tool to register
  # @return [FastMcp::Tool] The registered tool
  def self.register_tool(tool)
    self.server ||= FastMcp::Server.new(name: 'mcp-server', version: '1.0.0')
    self.server.register_tool(tool)
  end

  # Register multiple tools at once
  # @param tools [Array<FastMcp::Tool>] The tools to register
  # @return [Array<FastMcp::Tool>] The registered tools
  def self.register_tools(*tools)
    self.server ||= FastMcp::Server.new(name: 'mcp-server', version: '1.0.0')
    self.server.register_tools(*tools)
  end

  # Register a resource with the MCP server
  # @param resource [FastMcp::Resource] The resource to register
  # @return [FastMcp::Resource] The registered resource
  def self.register_resource(resource)
    self.server ||= FastMcp::Server.new(name: 'mcp-server', version: '1.0.0')
    self.server.register_resource(resource)
  end

  # Register multiple resources at once
  # @param resources [Array<FastMcp::Resource>] The resources to register
  # @return [Array<FastMcp::Resource>] The registered resources
  def self.register_resources(*resources)
    self.server ||= FastMcp::Server.new(name: 'mcp-server', version: '1.0.0')
    self.server.register_resources(*resources)
  end

  # Mount the MCP middleware in a Rails application
  # @param app [Rails::Application] The Rails application
  # @param options [Hash] Options for the middleware
  # @option options [String] :name The name of the server
  # @option options [String] :version The version of the server
  # @option options [Symbol] :transport The transport type (:streamable_http, :legacy, :oauth)
  # @option options [String] :path The path for the MCP endpoint (for StreamableHTTP)
  # @option options [String] :path_prefix The path prefix for the MCP endpoints (legacy)
  # @option options [String] :messages_route The route for the messages endpoint (legacy)
  # @option options [String] :sse_route The route for the SSE endpoint (legacy)
  # @option options [Logger] :logger The logger to use
  # @option options [Boolean] :authenticate Whether to use authentication
  # @option options [String] :auth_token The authentication token
  # @option options [Boolean] :oauth_enabled Whether to use OAuth 2.1
  # @option options [Proc] :opaque_token_validator OAuth token validator
  # @option options [Array<String,Regexp>] :allowed_origins List of allowed origins for DNS rebinding protection
  # @yield [server] A block to configure the server
  # @yieldparam server [FastMcp::Server] The server to configure
  # @return [#call] The Rack middleware
  def self.mount_in_rails(app, options = {}, &block)
    
    # Default options
    name = options.delete(:name) || app.class.module_parent_name.underscore.dasherize
    version = options.delete(:version) || '1.0.0'
    logger = options[:logger] || Rails.logger
    transport_type = options.delete(:transport) || detect_transport_type(options)

    # Handle transport-specific options
    if transport_type == :legacy
      setup_legacy_rails_transport(app, options.merge(name: name, version: version, logger: logger), &block)
    else
      setup_streamable_rails_transport(app, options.merge(name: name, version: version, logger: logger), transport_type, &block)
    end
  end

  def self.detect_transport_type(options)
    # Detect transport type based on options
    return :oauth if options[:oauth_enabled] || options[:opaque_token_validator]
    return :legacy if options[:path_prefix] || options[:messages_route] || options[:sse_route]
    return :authenticated if options[:authenticate] || options[:auth_token]

    :streamable_http # Default to modern transport
  end

  def self.setup_legacy_rails_transport(app, options, &block)
    # Legacy transport setup with deprecation warning
    warn_rails_legacy_usage

    path_prefix = options.delete(:path_prefix) || '/mcp'
    messages_route = options.delete(:messages_route) || 'messages'
    sse_route = options.delete(:sse_route) || 'sse'
    authenticate = options.delete(:authenticate) || false
    allowed_origins = options[:allowed_origins] || default_rails_allowed_origins(app)
    allowed_ips = options[:allowed_ips] || FastMcp::Transports::RackTransport::DEFAULT_ALLOWED_IPS

    options[:localhost_only] = Rails.env.local? if options[:localhost_only].nil?
    options[:allowed_ips] = allowed_ips
    options[:allowed_origins] = allowed_origins

    # Create server
    self.server = FastMcp::Server.new(name: options[:name], version: options[:version], logger: options[:logger])
    yield self.server if block_given?

    # Choose legacy transport
    transport_klass = if authenticate
                        FastMcp::Transports::AuthenticatedRackTransport
                      else
                        FastMcp::Transports::RackTransport
                      end

    # Insert middleware
    app.middleware.use(
      transport_klass,
      self.server,
      options.merge(
        path_prefix: path_prefix,
        messages_route: messages_route,
        sse_route: sse_route,
        warn_deprecation: true
      )
    )
  end

  def self.setup_streamable_rails_transport(app, options, transport_type, &block)
    path = options.delete(:path) || '/mcp'
    allowed_origins = options[:allowed_origins] || default_rails_allowed_origins(app)
    allowed_ips = options[:allowed_ips] || ['127.0.0.1', '::1', '::ffff:127.0.0.1']

    options[:localhost_only] = Rails.env.local? if options[:localhost_only].nil?
    options[:allowed_ips] = allowed_ips
    options[:allowed_origins] = allowed_origins
    options[:require_https] = Rails.env.production? if options[:require_https].nil?

    # Create server
    self.server = FastMcp::Server.new(name: options[:name], version: options[:version], logger: options[:logger])
    yield self.server if block_given?

    # Choose modern transport
    transport_klass = case transport_type
                      when :oauth
                        FastMcp::Transports::OAuthStreamableHttpTransport
                      when :authenticated
                        FastMcp::Transports::AuthenticatedStreamableHttpTransport
                      else
                        FastMcp::Transports::StreamableHttpTransport
                      end

    # Insert middleware
    app.middleware.use(
      transport_klass,
      self.server,
      options.merge(path: path)
    )
  end

  def self.warn_rails_legacy_usage
    Rails.logger.warn('DEPRECATION WARNING: Legacy MCP transport detected in mount_in_rails.')
    Rails.logger.warn('Please migrate to StreamableHTTP transport for MCP 2025-06-18 compliance.')
    Rails.logger.warn('See migration guide: https://github.com/yjacquin/fast-mcp/blob/main/docs/migration_guide.md')
  end

  def self.default_rails_allowed_origins(rail_app)
    hosts = rail_app.config.hosts

    hosts.map do |host|
      if host.is_a?(String) && host.start_with?('.')
        # Convert .domain to domain and *.domain
        host_without_dot = host[1..]
        [host_without_dot, Regexp.new(".*\.#{host_without_dot}")] # rubocop:disable Style/RedundantStringEscape
      else
        host
      end
    end.flatten.compact
  end

  # Notify the server that a resource has been updated
  # @param uri [String] The URI of the resource
  def self.notify_resource_updated(uri)
    self.server.notify_resource_updated(uri)
  end
end
