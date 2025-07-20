#!/usr/bin/env ruby
# frozen_string_literal: true

# Example server with StreamableHTTP transport (MCP 2025-06-18)
# This demonstrates the new unified endpoint transport

require_relative '../lib/fast_mcp'
require 'rack'
require 'puma'

# Example tool that lists files in a directory
class ListFilesTool < FastMcp::Tool
  tool_name 'list_files'
  description 'List files in a directory'

  arguments do
    required(:directory).filled(:string).description('The directory to list files from')
    optional(:pattern).filled(:string).description('A pattern to filter files')
  end

  def call(directory:, pattern: nil)
    return { error: 'Directory not found' } unless Dir.exist?(directory)

    files = if pattern
              Dir.glob(File.join(directory, pattern))
            else
              Dir.entries(directory).reject { |f| f.start_with?('.') }
            end

    { files: files.map { |f| File.basename(f) } }
  rescue StandardError => e
    { error: "Failed to list files: #{e.message}" }
  end
end

# Example resource that provides file content
class FileResource < FastMcp::Resource
  resource_name 'file'
  description 'Read file contents'
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
    '<h1>StreamableHTTP MCP Server</h1>',
    '<p>This server provides MCP services at <a href="/mcp">/mcp</a></p>',
    '<p>Test with: <code>npx @modelcontextprotocol/inspector http://localhost:3001/mcp</code></p>',
    '</body></html>'
  ]]
end

# Create and configure the MCP server
mcp_server = FastMcp::Server.new(
  name: 'StreamableHTTP Example Server',
  version: '1.0.0'
)

# Add tools and resources
mcp_server.register_tools(ListFilesTool)
mcp_server.register_resource(FileResource)

# Create StreamableHTTP transport as Rack middleware
transport = FastMcp::Transports::StreamableHttpTransport.new(
  main_app,
  mcp_server,
  logger: Logger.new($stdout, level: Logger::DEBUG),
  path: '/mcp'
)

if __FILE__ == $0
  puts 'Starting StreamableHTTP MCP Server...'
puts 'Server will be available at: http://localhost:3001'
puts 'Available endpoints:'
puts '  GET  / - Main application'
puts '  POST /mcp - JSON-RPC endpoint'
puts '  GET  /mcp (with Accept: text/event-stream) - SSE streaming'
puts ''
puts 'Test with MCP Inspector:'
puts '  npx @modelcontextprotocol/inspector http://localhost:3001/mcp'
puts ''
puts 'Example curl commands:'
puts '  # List tools'
puts '  curl -X POST http://localhost:3001/mcp \\'
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
