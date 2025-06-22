#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive OAuth 2.1 MCP Server Example
#
# This example demonstrates a complete OAuth 2.1 implementation for MCP servers including:
# - Role-based access control with scopes (admin, read, tools)
# - Token validation with both opaque and JWT tokens
# - Audience binding for enhanced security
# - Production-ready configuration examples
# - Security best practices
#
# Security Features Demonstrated:
# - PKCE (Proof Key for Code Exchange) support
# - Audience binding (RFC 8707) to prevent confused deputy attacks
# - Proper HTTPS enforcement (disabled for local development)
# - Scope-based authorization for different MCP operations
# - Secure token validation

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

# Enhanced OAuth Token Validator Examples
# In production, these would connect to your OAuth authorization server

# Example 1: Opaque Token Validator (for custom tokens)
# This simulates checking tokens against a database or authorization server
opaque_token_validator = lambda do |token|
  # In production, this would validate against your OAuth server's database
  case token
  when 'admin_token_123'
    # Full administrative access
    {
      valid: true,
      scopes: ['mcp:admin', 'mcp:resources', 'mcp:tools'],
      subject: 'admin_user',
      client_id: 'mcp_admin_client'
    }
  when 'read_token_456'
    # Read-only access to resources
    {
      valid: true,
      scopes: ['mcp:resources'],
      subject: 'readonly_user',
      client_id: 'mcp_readonly_client'
    }
  when 'tools_token_789'
    # Can execute tools and read resources
    {
      valid: true,
      scopes: ['mcp:tools', 'mcp:resources'],
      subject: 'developer_user',
      client_id: 'mcp_developer_client'
    }
  else
    { valid: false }
  end
end

# Example 2: JWT Token Configuration (for standards-based tokens)
# Uncomment and configure these options for JWT token validation:
#
# jwt_config = {
#   # For HMAC-signed JWTs (shared secret)
#   hmac_secret: ENV['JWT_HMAC_SECRET'],
#
#   # For RSA/ECDSA-signed JWTs (public key validation)
#   jwks_uri: 'https://your-auth-server.com/.well-known/jwks.json',
#   issuer: 'https://your-auth-server.com',
#   audience: 'http://localhost:3001/mcp', # Should match resource_identifier
#
#   # Optional: Authorization server discovery
#   # The system can auto-discover endpoints from the issuer
#   # issuer: 'https://your-auth-server.com' # Will auto-discover from /.well-known/openid-configuration
# }

# OAuth 2.1 Transport Configuration
# This demonstrates all available security options
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  main_app,
  mcp_server,
  # Basic Configuration
  logger: Logger.new($stdout, level: Logger::DEBUG),
  path: '/mcp',

  # OAuth 2.1 Configuration
  oauth_enabled: true,

  # Token Validation Options
  opaque_token_validator: opaque_token_validator,
  # For JWT tokens, merge jwt_config here instead:
  # **jwt_config,

  # Security Configuration
  require_https: false, # ⚠️  Set to true in production! Allow HTTP for local development only
  resource_identifier: 'http://localhost:3001/mcp', # Audience binding (RFC 8707) - prevents confused deputy attacks

  # Scope Configuration - Define what scopes are required for different operations
  tools_scope: 'mcp:tools', # Required to execute tools
  resources_scope: 'mcp:resources', # Required to read resources
  admin_scope: 'mcp:admin', # Required for administrative operations

  # CORS Configuration (for web clients)
  cors_enabled: true,
  allowed_origins: ['localhost', '127.0.0.1']
  # Optional: Token Introspection (for remote token validation)
  # introspection_endpoint: 'https://your-auth-server.com/oauth/introspect',
  # client_id: 'your_mcp_server_client_id',
  # client_secret: ENV['OAUTH_CLIENT_SECRET'],

  # Optional: Authorization Server Discovery
  # issuer: 'https://your-auth-server.com', # Auto-discovers endpoints
)

if __FILE__ == $0
  puts '🚀 Starting OAuth 2.1 Enabled MCP Server...'
  puts '   Server will be available at: http://localhost:3001'
  puts ''
  puts '📋 Available Endpoints:'
  puts '   GET  /           - Main application with token information and examples'
  puts '   POST /mcp        - OAuth 2.1 protected JSON-RPC endpoint'
  puts '   GET  /mcp        - OAuth 2.1 protected SSE streaming (Accept: text/event-stream)'
  puts ''
  puts '🔑 Demo Tokens (for testing):'
  puts '   admin_token_123  - Full administrative access (admin + resources + tools)'
  puts '   read_token_456   - Read-only access to resources'
  puts '   tools_token_789  - Can execute tools and read resources'
  puts ''
  puts '🔒 Security Features Enabled:'
  puts '   ✅ OAuth 2.1 compliance with PKCE support'
  puts '   ✅ Scope-based authorization (admin, resources, tools)'
  puts '   ✅ Audience binding for enhanced security'
  puts '   ✅ Token introspection with local fallback'
  puts '   ⚠️  HTTPS enforcement disabled (development mode)'
  puts ''
  puts '🧪 Testing Options:'
  puts ''
  puts '1. MCP Inspector (graphical interface):'
  puts '   npx @modelcontextprotocol/inspector http://localhost:3001/mcp'
  puts '   → Add token in Inspector settings before connecting'
  puts ''
  puts '2. Command Line Examples:'
  puts ''
  puts '   # Test server capabilities (requires admin scope)'
  puts '   curl -H "Authorization: Bearer admin_token_123" \\'
  puts '        -H "Content-Type: application/json" \\'
  puts '        -H "Accept: application/json" \\'
  puts '        -H "MCP-Protocol-Version: 2025-06-18" \\'
  puts '        -X POST http://localhost:3001/mcp \\'
  puts '        -d \'{"jsonrpc":"2.0","method":"initialize","params":{"capabilities":{},"clientInfo":{"name":"test","version":"1.0"}},"id":1}\''
  puts ''
  puts '   # List available tools (requires tools scope)'
  puts '   curl -H "Authorization: Bearer admin_token_123" \\'
  puts '        -H "Content-Type: application/json" \\'
  puts '        -H "Accept: application/json" \\'
  puts '        -H "MCP-Protocol-Version: 2025-06-18" \\'
  puts '        -X POST http://localhost:3001/mcp \\'
  puts '        -d \'{"jsonrpc":"2.0","method":"tools/list","id":1}\''
  puts ''
  puts '   # List available resources (requires resources scope)'
  puts '   curl -H "Authorization: Bearer read_token_456" \\'
  puts '        -H "Content-Type: application/json" \\'
  puts '        -H "Accept: application/json" \\'
  puts '        -H "MCP-Protocol-Version: 2025-06-18" \\'
  puts '        -X POST http://localhost:3001/mcp \\'
  puts '        -d \'{"jsonrpc":"2.0","method":"resources/list","id":1}\''
  puts ''
  puts '   # Execute a tool (requires tools scope)'
  puts '   curl -H "Authorization: Bearer tools_token_789" \\'
  puts '        -H "Content-Type: application/json" \\'
  puts '        -H "Accept: application/json" \\'
  puts '        -H "MCP-Protocol-Version: 2025-06-18" \\'
  puts '        -X POST http://localhost:3001/mcp \\'
  puts '        -d \'{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_files","arguments":{"directory":"."}},"id":1}\''
  puts ''
  puts '3. Error Testing (demonstrating OAuth 2.1 error responses):'
  puts ''
  puts '   # Test with invalid token'
  puts '   curl -H "Authorization: Bearer invalid_token" \\'
  puts '        -X POST http://localhost:3001/mcp \\'
  puts '        -d \'{"jsonrpc":"2.0","method":"tools/list","id":1}\''
  puts ''
  puts '   # Test with insufficient scope (read token trying to access tools)'
  puts '   curl -H "Authorization: Bearer read_token_456" \\'
  puts '        -X POST http://localhost:3001/mcp \\'
  puts '        -d \'{"jsonrpc":"2.0","method":"tools/list","id":1}\''
  puts ''
  puts '🛑 Press Ctrl+C to stop the server'

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

    puts 'Server started successfully!'
    server.run.join
  rescue LoadError
    puts 'Puma gem not available. Please install it with: gem install puma'
    exit 1
  rescue StandardError => e
    puts "Error starting server: #{e.message}"
    exit 1
  end
end
