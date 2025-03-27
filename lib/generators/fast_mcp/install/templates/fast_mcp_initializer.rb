# frozen_string_literal: true

# FastMcp - Model Context Protocol for Rails
# This initializer sets up the MCP middleware in your Rails application.

# Mount the MCP middleware in your Rails application
# You can customize the options below to fit your needs.
require 'fast_mcp'

FastMcp.mount_in_rails(
  Rails.application,
  name: Rails.application.class.module_parent_name.underscore.dasherize,
  version: '1.0.0',
  path_prefix: '/mcp' # This is the default path prefix
  # authenticate: true,       # Uncomment to enable authentication
  # auth_token: 'your-token', # Required if authenticate: true
) do |server|
  Rails.application.config.after_initialize do
    # FastMcpwill automatically discover and register:
    # - All classes that inherit from ApplicationTool
    # - All classes that inherit from ApplicationResource
    server.register_tools(*ApplicationTool.descendants)
    server.register_resources(*ApplicationResource.descendants)
    # alternatively, you can register tools and resources manually:
    # server.register_tool(MyTool)
    # server.register_resource(MyResource)
  end
end
