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
  # Transport type - options: :streamable_http, :authenticated, :oauth, :legacy
  transport: :streamable_http, # Modern MCP 2025-06-18 transport (recommended)

  # Basic configuration
  name: Rails.application.class.module_parent_name.underscore.dasherize,
  version: '1.0.0',
  path: '/mcp', # Single unified endpoint for StreamableHTTP

  # Security settings
  require_https: Rails.env.production?,
  localhost_only: Rails.env.local?,
  allowed_origins: Rails.application.config.hosts
  # Authentication options (uncomment one):
  #
  # Option 1: No authentication (development only)
  # (no additional config needed - current configuration)
  #
  # Option 2: Simple token authentication
  # transport: :authenticated,
  # auth_token: Rails.application.credentials.mcp_token,
  #
  # Option 3: OAuth 2.1 authorization (production recommended)
  # transport: :oauth,
  # oauth_enabled: true,
  # opaque_token_validator: method(:validate_oauth_token),
  # require_https: true,
  #
  # Legacy transport (deprecated - use only for migration)
  # transport: :legacy,
  # path_prefix: '/mcp',
  # messages_route: 'messages',
  # sse_route: 'sse'
) do |server|
  Rails.application.config.after_initialize do
    # FastMcp will automatically discover and register:
    # - All classes that inherit from ApplicationTool (which uses ActionTool::Base)
    # - All classes that inherit from ApplicationResource (which uses ActionResource::Base)
    server.register_tools(*ApplicationTool.descendants)
    server.register_resources(*ApplicationResource.descendants)

    # Alternatively, you can register tools and resources manually:
    # server.register_tool(MyTool)
    # server.register_resource(MyResource)
  end
end

# OAuth 2.1 token validator (uncomment if using OAuth transport)
# def validate_oauth_token(token)
#   # Implement your OAuth token validation here
#   # This example shows validation against an OAuth introspection endpoint
#
#   begin
#     response = HTTParty.post(
#       Rails.application.credentials.oauth[:introspection_endpoint],
#       body: { token: token },
#       headers: {
#         'Authorization' => "Basic #{Rails.application.credentials.oauth[:client_credentials]}",
#         'Content-Type' => 'application/x-www-form-urlencoded'
#       }
#     )
#
#     if response.success? && response.parsed['active']
#       {
#         valid: true,
#         scopes: response.parsed['scope']&.split(' ') || [],
#         subject: response.parsed['sub'],
#         client_id: response.parsed['client_id'],
#         expires_at: response.parsed['exp'] ? Time.at(response.parsed['exp']) : nil
#       }
#     else
#       { valid: false }
#     end
#   rescue StandardError => e
#     Rails.logger.error("OAuth token validation failed: #{e.message}")
#     { valid: false }
#   end
# end

# Configuration examples for different environments:
#
# Development:
#   transport: :streamable_http (no auth)
#   localhost_only: true
#   require_https: false
#
# Staging:
#   transport: :authenticated
#   auth_token: Rails.application.credentials.mcp_token
#   require_https: true
#
# Production:
#   transport: :oauth
#   oauth_enabled: true
#   opaque_token_validator: method(:validate_oauth_token)
#   require_https: true
