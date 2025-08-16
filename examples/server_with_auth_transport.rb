#!/usr/bin/env ruby
# frozen_string_literal: true

# Example server with Authenticated StreamableHTTP transport
# This demonstrates token-based authentication for MCP servers

require_relative '../lib/fast_mcp'
require 'rack'
require 'puma'

# Example tool
class GreetTool < FastMcp::Tool
  tool_name 'greet'
  description 'Greet someone with a personalized message'

  arguments do
    required(:name).filled(:string).description('The name of the person to greet')
    optional(:style).filled(:string).value(included_in?: %w[casual formal]).description('The greeting style')
  end

  def call(name:, style: 'casual')
    greeting = case style
               when 'formal'
                 "Good day, #{name}. I hope you are well."
               else
                 "Hey #{name}! How's it going?"
               end

    { message: greeting, style: style }
  end
end

# Example resource
class TimeResource < FastMcp::Resource
  resource_name 'time'
  description 'Current server time'
  uri 'time://current'

  def content
    {
      current_time: Time.now.iso8601,
      timezone: Time.now.zone,
      unix_timestamp: Time.now.to_i
    }.to_json
  end
end

# Create a simple Rack application for the main site
main_app = lambda do |_env|
  [200, { 'Content-Type' => 'text/html' }, [
    '<html><body>',
    '<h1>Authenticated StreamableHTTP MCP Server</h1>',
    '<p>This server provides token-authenticated MCP services at <a href="/mcp">/mcp</a></p>',
    '<p>Authentication token: <code>secret-token-123</code></p>',
    '<p>Test with: <code>npx @modelcontextprotocol/inspector http://localhost:3001/mcp</code></p>',
    '<p>Make sure to set the Authorization header to: <code>Bearer secret-token-123</code></p>',
    '</body></html>'
  ]]
end

# Create and configure the MCP server
mcp_server = FastMcp::Server.new(
  name: 'Authenticated StreamableHTTP Example Server',
  version: '1.0.0'
)

# Add tools and resources
mcp_server.register_tools(GreetTool)
mcp_server.register_resource(TimeResource)

# Create Authenticated StreamableHTTP transport as Rack middleware
transport = FastMcp::Transports::AuthenticatedStreamableHttpTransport.new(
  main_app,
  mcp_server,
  logger: Logger.new($stdout, level: Logger::INFO),
  path: '/mcp',
  auth_token: 'secret-token-123'
)

if __FILE__ == $PROGRAM_NAME
  puts 'Starting Authenticated StreamableHTTP MCP Server...'
  puts 'Server will be available at: http://localhost:3001'
  puts 'Available endpoints:'
  puts '  GET  / - Main application'
  puts '  POST /mcp - Token-authenticated JSON-RPC endpoint'
  puts '  GET  /mcp (with Accept: text/event-stream) - Token-authenticated SSE streaming'
  puts ''
  puts 'Authentication token: secret-token-123'
  puts ''
  puts 'Test with MCP Inspector (add Bearer token in settings):'
  puts '  npx @modelcontextprotocol/inspector http://localhost:3001/mcp'
  puts ''
  puts 'Example curl commands:'
  puts '  # Without authentication (should fail)'
  puts '  curl -X POST http://localhost:3001/mcp \\'
  puts '    -H "Content-Type: application/json" \\'
  puts '    -d \'{"jsonrpc":"2.0","method":"tools/list","id":1}\''
  puts ''
  puts '  # With authentication (should succeed)'
  puts '  curl -H "Authorization: Bearer secret-token-123" -X POST http://localhost:3001/mcp \\'
  puts '    -H "Content-Type: application/json" \\'
  puts '    -H "Accept: application/json" \\'
  puts '    -H "MCP-Protocol-Version: 2025-06-18" \\'
  puts '    -d \'{"jsonrpc":"2.0","method":"tools/list","id":1}\''
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
