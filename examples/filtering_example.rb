#!/usr/bin/env ruby
# frozen_string_literal: true

# Example of using dynamic tool filtering with MCP

require 'bundler/setup'
require 'fast_mcp'
require 'rack'
require 'rack/handler/puma'

# Define tools with different permission levels
class PublicWeatherTool < FastMcp::Tool
  tool_name 'get_weather'
  description 'Get current weather for a location'
  tags :public, :read_only

  arguments do
    required(:location).filled(:string).description('Location to get weather for')
  end

  def call(location:)
    # Simulated weather data
    {
      location: location,
      temperature: rand(60..85),
      conditions: ['Sunny', 'Cloudy', 'Partly Cloudy'].sample,
      humidity: rand(30..70)
    }
  end
end

class UserProfileTool < FastMcp::Tool
  tool_name 'update_profile'
  description 'Update user profile information'
  tags :user, :write

  arguments do
    required(:user_id).filled(:integer).description('User ID')
    optional(:name).filled(:string).description('New name')
    optional(:email).filled(:string).description('New email')
  end

  def call(user_id:, name: nil, email: nil)
    updates = {}
    updates[:name] = name if name
    updates[:email] = email if email

    {
      user_id: user_id,
      updated: updates,
      success: true
    }
  end
end

class AdminSystemTool < FastMcp::Tool
  tool_name 'system_shutdown'
  description 'Shutdown the system'
  tags :admin, :dangerous, :system

  arguments do
    required(:confirm).filled(:bool).description('Confirm shutdown')
    optional(:delay).filled(:integer).description('Delay in seconds')
  end

  def call(confirm:, delay: 0)
    return { error: 'Shutdown not confirmed' } unless confirm

    {
      action: 'shutdown',
      delay: delay,
      scheduled_at: Time.now + delay
    }
  end
end

class AdminUserManagementTool < FastMcp::Tool
  tool_name 'delete_user'
  description 'Delete a user account'
  tags :admin, :dangerous, :user_management
  metadata :requires_approval, true
  metadata :audit_level, 'high'

  arguments do
    required(:user_id).filled(:integer).description('User ID to delete')
    required(:reason).filled(:string).description('Reason for deletion')
  end

  def call(user_id:, reason:)
    {
      user_id: user_id,
      deleted: true,
      reason: reason,
      deleted_at: Time.now
    }
  end
end

# Define resources with access levels
class PublicStatsResource < FastMcp::Resource
  uri 'stats/public'
  resource_name 'Public Statistics'
  description 'Publicly available system statistics'
  mime_type 'application/json'

  def self.tags
    [:public, :read_only]
  end

  def content
    JSON.generate({
                    total_users: 1234,
                    active_today: 567,
                    server_uptime: '99.9%'
                  })
  end
end

class AdminLogsResource < FastMcp::Resource
  uri 'logs/admin'
  resource_name 'System Logs'
  description 'Admin-only system logs'
  mime_type 'text/plain'

  def self.tags
    [:admin, :sensitive]
  end

  def content
    <<~LOGS
      [2024-01-01 10:00:00] INFO: System started
      [2024-01-01 10:15:00] WARN: High memory usage detected
      [2024-01-01 10:30:00] INFO: Backup completed successfully
    LOGS
  end
end

# Create a simple Rack application
app = lambda do |env|
  request = Rack::Request.new(env)

  html = <<~HTML
    <html>
      <head>
        <title>MCP Filtering Example</title>
        <style>
          body { font-family: sans-serif; margin: 40px; }
          .section { margin: 20px 0; padding: 20px; border: 1px solid #ddd; border-radius: 5px; }
          .role { font-weight: bold; color: #0066cc; }
          code { background: #f4f4f4; padding: 2px 4px; border-radius: 3px; }
        </style>
      </head>
      <body>
        <h1>Dynamic Tool Filtering Example</h1>
    #{'    '}
        <div class="section">
          <h2>How to Test</h2>
          <p>This server demonstrates dynamic tool filtering based on user roles.</p>
          <p>Tools and resources are filtered based on the <code>role</code> query parameter.</p>
    #{'      '}
          <h3>Try these endpoints:</h3>
          <ul>
            <li><strong>Public access:</strong> <code>/mcp/messages</code> (no role parameter)</li>
            <li><strong>User access:</strong> <code>/mcp/messages?role=user</code></li>
            <li><strong>Admin access:</strong> <code>/mcp/messages?role=admin</code></li>
          </ul>
    #{'      '}
          <h3>Available Tools by Role:</h3>
          <ul>
            <li><span class="role">Public:</span> get_weather</li>
            <li><span class="role">User:</span> get_weather, update_profile</li>
            <li><span class="role">Admin:</span> All tools (including system_shutdown, delete_user)</li>
          </ul>
        </div>
    #{'    '}
        <div class="section">
          <h2>Testing with MCP Inspector</h2>
          <p>1. In the MCP Inspector, select <strong>SSE</strong> transport</p>
          <p>2. Use one of these URLs:</p>
          <ul>
            <li><code>http://localhost:9292/mcp</code> - Public access</li>
            <li><code>http://localhost:9292/mcp?role=user</code> - User access</li>
            <li><code>http://localhost:9292/mcp?role=admin</code> - Admin access</li>
          </ul>
          <p>3. Click "Connect" and explore the available tools</p>
        </div>
    #{'    '}
        <div class="section">
          <h2>Current Request Info</h2>
          <p><strong>Path:</strong> #{request.path}</p>
          <p><strong>Role:</strong> #{request.params['role'] || 'public'}</p>
        </div>
      </body>
    </html>
  HTML

  [200, { 'Content-Type' => 'text/html' }, [html]]
end

# Create the MCP middleware with filtering
mcp_app = FastMcp.rack_middleware(
  app,
  name: 'filtering-example',
  version: '1.0.0',
  logger: Logger.new($stdout)
) do |server|
  # Register all tools
  server.register_tools(
    PublicWeatherTool,
    UserProfileTool,
    AdminSystemTool,
    AdminUserManagementTool
  )

  # Register all resources
  server.register_resources(
    PublicStatsResource,
    AdminLogsResource
  )

  # Add tool filtering based on role
  server.filter_tools do |request, tools|
    role = request.params['role']

    puts "Filtering tools for role: #{role || 'public'}"

    case role
    when 'admin'
      # Admins see all tools
      puts "  -> Admin: returning all #{tools.size} tools"
      tools
    when 'user'
      # Users see public and user tools
      filtered = tools.reject { |t| t.tags.include?(:admin) }
      puts "  -> User: filtered to #{filtered.size} tools"
      filtered
    else
      # Public users only see public tools
      filtered = tools.select { |t| t.tags.include?(:public) }
      puts "  -> Public: filtered to #{filtered.size} tools"
      filtered
    end
  end

  # Add resource filtering based on role
  server.filter_resources do |request, resources|
    role = request.params['role']

    puts "Filtering resources for role: #{role || 'public'}"

    case role
    when 'admin'
      # Admins see all resources
      resources
    when 'user'
      # Users see public resources
      resources.reject { |r| r.respond_to?(:tags) && r.tags.include?(:admin) }
    else
      # Public users only see public resources
      resources.select { |r| r.respond_to?(:tags) && r.tags.include?(:public) }
    end
  end

  # Example of metadata-based filtering
  server.filter_tools do |request, tools|
    # Check if audit mode is enabled
    if request.params['audit_mode'] == 'true'
      # In audit mode, exclude tools that require approval
      tools.reject { |t| t.metadata(:requires_approval) == true }
    else
      tools
    end
  end
end

# Run the server
puts '=' * 60
puts 'MCP Dynamic Filtering Example'
puts '=' * 60
puts 'Server running on http://localhost:9292'
puts ''
puts 'Test URLs:'
puts '  - http://localhost:9292 (Web interface)'
puts '  - http://localhost:9292/mcp/sse (SSE endpoint - Public)'
puts '  - http://localhost:9292/mcp/sse?role=user (SSE endpoint - User)'
puts '  - http://localhost:9292/mcp/sse?role=admin (SSE endpoint - Admin)'
puts ''
puts 'To test with MCP Inspector:'
puts '  npx @modelcontextprotocol/inspector'
puts '  Then select SSE and use one of the URLs above'
puts '=' * 60

# Use Puma server
require 'puma'
require 'puma/configuration'
require 'puma/launcher'

app_builder = Rack::Builder.new { run mcp_app }
config = Puma::Configuration.new do |user_config|
  user_config.bind 'tcp://localhost:9292'
  user_config.app app_builder
end

launcher = Puma::Launcher.new(config)
launcher.run
