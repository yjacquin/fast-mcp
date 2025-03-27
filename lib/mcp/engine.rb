# # frozen_string_literal: true

# module FastMcp
#   # Rails engine for MCP to handle routes
#   class Engine < ::Rails::Engine
#     isolate_namespace FastMcp

#     initializer 'fast_mcp.middleware' do |app|
#       # Add the MCP middleware to the Rails application
#       app.middleware.use MCP::Transports::RackTransport, app, {
#         path_prefix: '/mcp',
#         name: app.class.module_parent_name.underscore.dasherize,
#         version: '1.0.0',
#         logger: Rails.logger,
#         server: FastMcp.server
#       }
#     end

#     # Initialize MCP server instance
#     config.before_initialize do
#       # Create the server instance if not created yet
#       FastMcp.server ||= MCP::Server.new(
#         name: Rails.application.class.module_parent_name.underscore.dasherize,
#         version: '1.0.0',
#         logger: Rails.logger
#       )
#     end

#     # Auto-register tools and resources from the Rails app
#     config.after_initialize do
#       # Register all tools
#       if defined?(::Tools)
#         ::Tools.constants.each do |const|
#           tool_class = ::Tools.const_get(const)
#           FastMcp.server.register_tool(tool_class) if tool_class.is_a?(Class) && tool_class < MCP::Tool
#         end
#       end

#       # Register all resources
#       if defined?(::Resources)
#         ::Resources.constants.each do |const|
#           resource_class = ::Resources.const_get(const)
#           if resource_class.is_a?(Class) && resource_class < MCP::Resource &&
#              resource_class.respond_to?(:initialize_singleton)
#             resource_class.initialize_singleton(FastMcp.server)
#           end
#         end
#       end
#     end
#   end
# end
