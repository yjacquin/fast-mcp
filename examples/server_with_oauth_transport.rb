#!/usr/bin/env ruby
# frozen_string_literal: true

# Example server with OAuth 2.1 enabled StreamableHTTP transport
# This demonstrates OAuth-based authorization for MCP servers

require_relative '../lib/fast_mcp'
require 'rack'
require 'puma'

# Example admin tool (requires mcp:admin scope)
class ServerStatusTool < FastMcp::Tool
  tool_name 'server_status'
  description 'Get server status information (requires admin privileges)'

  arguments do
    optional(:detailed).filled(:bool).description('Whether to include detailed status information')
  end

  def call(detailed: false)
    status = {
      status: 'running',
      uptime: Time.now.to_i,
      version: '1.0.0'
    }

    if detailed
      status.merge!(
        memory_usage: `ps -o rss= -p #{Process.pid}`.strip.to_i,
        cpu_usage: rand(1.0..10.0).round(2)
      )
    end

    status
  end
end

# Example read-only tool (requires mcp:read scope)
class ListFilesTool < FastMcp::Tool
  tool_name 'list_files'
  description 'List files in a directory (requires read access)'

  arguments do
    required(:directory).filled(:string).description('The directory to list files from')
    optional(:pattern).filled(:string).description('A pattern to filter files')
  end

  def call(directory:, pattern: nil)
    return error('Directory not found') unless Dir.exist?(directory)

    files = if pattern
              Dir.glob(File.join(directory, pattern))
            else
              Dir.entries(directory).reject { |f| f.start_with?('.') }
            end

    success(files: files.map { |f| File.basename(f) })
  rescue StandardError => e
    error("Failed to list files: #{e.message}")
  end
end

# Example resource (requires mcp:read scope)
class FileResource < FastMcp::Resource
  resource_name 'File'
  description 'Read file contents (requires read access)'
  uri 'file:///{path}'

  def content(path:)
    raise 'File not found' unless File.exist?(path)

    File.read(path)
  end
end

# Create a simple Rack application for the main site
main_app = lambda do |_env|
  [200, { 'Content-Type' => 'text/html' }, [
    '<html><body>',
    '<h1>OAuth StreamableHTTP MCP Server</h1>',
    '<p>This server provides OAuth-protected MCP services at <a href="/mcp">/mcp</a></p>',
    '<p>Test with: <code>npx @modelcontextprotocol/inspector http://localhost:3001/mcp</code></p>',
    '<h3>Test Tokens:</h3>',
    '<ul>',
    '<li><code>admin_token_123</code> - Full access (admin, read, write, tools)</li>',
    '<li><code>read_token_456</code> - Read-only access</li>',
    '<li><code>tools_token_789</code> - Tools and read access</li>',
    '</ul>',
    '</body></html>'
  ]]
end

# Create and configure the MCP server
mcp_server = FastMcp::Server.new(
  name: 'OAuth StreamableHTTP Example Server',
  version: '1.0.0'
)

# Add tools and resources
mcp_server.register_tools(ServerStatusTool, ListFilesTool)
mcp_server.register_resource(FileResource)

# Example opaque token validator
opaque_token_validator = lambda do |token|
  case token
  when 'admin_token_123'
    { valid: true, scopes: ['mcp:admin', 'mcp:read', 'mcp:write', 'mcp:tools'] }
  when 'read_token_456'
    { valid: true, scopes: ['mcp:read'] }
  when 'tools_token_789'
    { valid: true, scopes: ['mcp:tools', 'mcp:read'] }
  else
    { valid: false }
  end
end

# Create OAuth-enabled StreamableHTTP transport as Rack middleware
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  main_app,
  mcp_server,
  logger: Logger.new($stdout, level: Logger::DEBUG),
  path: '/mcp',
  oauth_enabled: true,
  opaque_token_validator: opaque_token_validator,
  require_https: false, # Allow HTTP for local development
  tools_scope: 'mcp:tools',
  resources_scope: 'mcp:read',
  admin_scope: 'mcp:admin'
)

if __FILE__ == $0
  puts 'Starting OAuth-enabled StreamableHTTP MCP Server...'
puts 'Server will be available at: http://localhost:3001'
puts 'Available endpoints:'
puts '  GET  / - Main application with token information'
puts '  POST /mcp - OAuth-protected JSON-RPC endpoint'
puts '  GET  /mcp (with Accept: text/event-stream) - OAuth-protected SSE streaming'
puts ''
puts 'Test tokens:'
puts '  admin_token_123 - Full access (admin, read, write, tools)'
puts '  read_token_456 - Read-only access'
puts '  tools_token_789 - Tools and read access'
puts ''
puts 'Test with MCP Inspector (add token in settings):'
puts '  npx @modelcontextprotocol/inspector http://localhost:3001/mcp'
puts ''
puts 'Example curl commands:'
puts '  # List tools (requires mcp:tools scope)'
puts '  curl -H "Authorization: Bearer admin_token_123" -X POST http://localhost:3001/mcp \\'
puts '    -H "Content-Type: application/json" \\'
puts '    -H "Accept: application/json" \\'
puts '    -H "MCP-Protocol-Version: 2025-06-18" \\'
puts '    -d \'{"jsonrpc":"2.0","method":"tools/list","id":1}\''
puts ''
puts '  # List resources (requires mcp:read scope)'
puts '  curl -H "Authorization: Bearer read_token_456" -X POST http://localhost:3001/mcp \\'
puts '    -H "Content-Type: application/json" \\'
puts '    -H "Accept: application/json" \\'
puts '    -H "MCP-Protocol-Version: 2025-06-18" \\'
puts '    -d \'{"jsonrpc":"2.0","method":"resources/list","id":1}\''
puts ''
puts 'Press Ctrl+C to stop'

# Start the HTTP server using Puma
begin
  require 'puma'
  
  # Create the Rack application
  app = Rack::Builder.new do
    run transport
  end
  
  # Create Puma server with proper configuration
  server = Puma::Server.new(app)
  server.add_tcp_listener('localhost', 3001)
  
  # Set up signal handlers
  Signal.trap('INT') do
    puts "\nShutting down..."
    server.stop
  end
  
  Signal.trap('TERM') do
    puts "\nShutting down..."
    server.stop
  end
  
  puts "Server started successfully!"
  server.run.join
rescue LoadError
  puts "Puma gem not available. Please install it with: gem install puma"
  exit 1
rescue StandardError => e
  puts "Error starting server: #{e.message}"
  exit 1
end
end
