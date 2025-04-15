# frozen_string_literal: true

# FastMcp - Model Context Protocol for Rails
# This initializer sets up the MCP middleware in your Rails application.
#
# In Rails applications, you can use:
# - ActionTool::Base as an alias for FastMcp::Tool
# - ActionResource::Base as an alias for FastMcp::Resource
#
# All your tools should inherit from ApplicationTool which already uses ActionTool::Base,
# and all your resources should inherit from ApplicationResource which uses ActionResource::Base.

# Mount the MCP middleware in your Rails application
# You can customize the options below to fit your needs.
require 'fast_mcp'

FastMcp.mount_in_rails(
  Rails.application,
  name: Rails.application.class.module_parent_name.underscore.dasherize,
  version: '1.0.0',
  path_prefix: '/mcp', # This is the default path prefix
  messages_route: 'messages', # This is the default route for the messages endpoint
  sse_route: 'sse' # This is the default route for the SSE endpoint
  # Add allowed origins below, it defaults to Rails.application.config.hosts
  # allowed_origins: ['localhost', '127.0.0.1', 'example.com', /.*\.example\.com/],

  # Authentication Configuration
  # --------------------------
  # authenticate: true,  # Uncomment to enable authentication
  # auth_options: {
  #   # Choose one of the authentication strategies below:
  #
  #   # 1. Token-based authentication (default)
  #   auth_strategy: :token,
  #   auth_token: 'your-secret-token',
  #   # auth_header: 'Authorization',  # Optional, defaults to 'Authorization'
  #   # Using X-API-Key instead of Authorization header:
  #   # auth_header: 'X-API-Key',  # Clients should send 'X-API-Key: your-secret-token'
  #
  #   # 2. Proc-based authentication
  #   # auth_strategy: :proc,
  #   # auth_proc: ->(request) {
  #   #   # Your custom authentication logic here
  #   #   # The entire request object is available
  #   #   token = request.get_header('HTTP_AUTHORIZATION')&.gsub(/^Bearer\s+/i, '')
  #   #   User.find_by(api_token: token).present?
  #   # },
  #
  #   # 3. HTTP Basic Authentication
  #   # auth_strategy: :http_basic,
  #   # auth_user: 'admin',
  #   # auth_password: 'secret',
  #
  #   # Additional Authentication Options
  #   # auth_exempt_paths: ['/health-check', '/mcp/public'],  # Paths that don't require authentication
  # },

  # Environment Variables for Authentication
  # ---------------------------------------
  # Instead of hardcoding authentication details, you can use environment variables:
  # - MCP_AUTH_TOKEN: The token for token-based authentication
  # - MCP_AUTH_HEADER: The header name for token-based auth (defaults to 'Authorization')
  # - MCP_AUTH_USER: The username for HTTP Basic authentication
  # - MCP_AUTH_PASSWORD: The password for HTTP Basic authentication
) do |server|
  Rails.application.config.after_initialize do
    # FastMcp will automatically discover and register:
    # - All classes that inherit from ApplicationTool (which uses ActionTool::Base)
    # - All classes that inherit from ApplicationResource (which uses ActionResource::Base)
    server.register_tools(*ApplicationTool.descendants)
    server.register_resources(*ApplicationResource.descendants)
    # alternatively, you can register tools and resources manually:
    # server.register_tool(MyTool)
    # server.register_resource(MyResource)
  end
end
