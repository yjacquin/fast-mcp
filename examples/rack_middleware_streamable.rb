#!/usr/bin/env ruby
# frozen_string_literal: true

# Example of using MCP with StreamableHTTP transport as Rack middleware
# This demonstrates the new MCP 2025-06-18 unified endpoint approach

require 'bundler/setup'
Bundler.require(:default, :examples)
require 'fast_mcp'
require 'rack'
require 'rack/handler/puma'

# Define tools using the class inheritance approach
class GreetTool < FastMcp::Tool
  description 'Greet a person'

  arguments do
    required(:name).filled(:string).description('The name of the person to greet')
  end

  def call(name:)
    "Hello, #{name}!"
  end
end

class CalculateTool < FastMcp::Tool
  description 'Perform a calculation'

  arguments do
    required(:operation).filled(:string).value(included_in?: %w[add subtract multiply
                                                                divide]).description('The operation to perform')
    required(:x).filled(:float).description('The first number')
    required(:y).filled(:float).description('The second number')
  end

  def call(operation:, x:, y:) # rubocop:disable Naming/MethodParameterName
    case operation
    when 'add'
      x + y
    when 'subtract'
      x - y
    when 'multiply'
      x * y
    when 'divide'
      x / y
    else
      raise "Unknown operation: #{operation}"
    end
  end
end

class HelloWorldResource < FastMcp::Resource
  uri 'file://hello_world'
  resource_name 'Hello World'
  description 'A simple hello world program'
  mime_type 'text/plain'

  def content
    'puts "Hello, world!"'
  end
end

# Create a simple Rack application
app = lambda do |_env|
  [200, { 'Content-Type' => 'text/html' },
   ['<html><body><h1>Hello from Rack!</h1><p>This is a simple Rack app with ' \
    'MCP StreamableHTTP middleware.</p></body></html>']]
end

# Create the MCP server
server = FastMcp::Server.new(
  name: 'StreamableHTTP Rack Example Server',
  version: '1.0.0'
)

# Register tools and resources
server.register_tools(GreetTool, CalculateTool)
server.register_resource(HelloWorldResource)

# Create StreamableHTTP transport middleware
mcp_transport = FastMcp::Transports::StreamableHttpTransport.new(
  app,
  server,
  logger: Logger.new($stdout, level: Logger::INFO),
  path: '/mcp'
)

puts 'Starting Rack application with MCP StreamableHTTP middleware on http://localhost:9292'
puts 'Available endpoints:'
puts '  - http://localhost:9292/ (Main Rack app)'
puts '  - http://localhost:9292/mcp (Unified MCP endpoint - POST for JSON-RPC, GET with SSE headers for streaming)'
puts ''
puts 'Test with MCP Inspector:'
puts '  npx @modelcontextprotocol/inspector http://localhost:9292/mcp'
puts ''
puts 'Example curl commands:'
puts '  # List tools'
puts '  curl -X POST http://localhost:9292/mcp -H "Content-Type: application/json" \\'
puts '    -d \'{"jsonrpc":"2.0","method":"tools/list","id":1}\''
puts ''
puts '  # Call greet tool'
puts '  curl -X POST http://localhost:9292/mcp -H "Content-Type: application/json" \\'
puts '    -d \'{"jsonrpc":"2.0","method":"tools/call","params":{"name":"greet","arguments":{"name":"World"}},"id":2}\''
puts ''
puts '  # SSE streaming'
puts '  curl -H "Accept: text/event-stream" http://localhost:9292/mcp'
puts ''
puts 'Press Ctrl+C to stop'

# Use the Puma server directly
require 'puma'
require 'puma/configuration'
require 'puma/launcher'

app = Rack::Builder.new { run mcp_transport }
config = Puma::Configuration.new do |user_config|
  user_config.bind 'tcp://localhost:9292'
  user_config.app app
end

launcher = Puma::Launcher.new(config)
launcher.run
