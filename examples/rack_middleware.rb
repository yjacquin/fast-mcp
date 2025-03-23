#!/usr/bin/env ruby
# frozen_string_literal: true

# Example of using MCP as a Rack middleware

require 'bundler/setup'
Bundler.require(:default, :examples)
require 'fast_mcp'
require 'rack'
require 'rack/handler/puma'

# Define tools using the class inheritance approach
class GreetTool < MCP::Tool
  description 'Greet a person'

  arguments do
    required(:name).filled(:string).description('The name of the person to greet')
  end

  def call(name:)
    "Hello, #{name}!"
  end
end

class CalculateTool < MCP::Tool
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

class HelloWorldResource < MCP::Resource
  uri 'file://hello_world'
  resource_name 'Hello World'
  description 'A simple hello world program'
  mime_type 'text/plain'

  def default_content
    'puts "Hello, world!"'
  end
end

# Create a simple Rack application
app = lambda do |_env|
  [200, { 'Content-Type' => 'text/html' },
   ['<html><body><h1>Hello from Rack!</h1><p>This is a simple Rack app with MCP middleware.</p></body></html>']]
end

# Create the MCP middleware
mcp_app = MCP.rack_middleware(app, name: 'example-mcp-server', version: '1.0.0') do |server|
  # Register tool classes
  server.register_tools(GreetTool, CalculateTool)

  # Register a sample resource
  server.register_resource(HelloWorldResource)
end

# Run the Rack application with Puma
puts 'Starting Rack application with MCP middleware on http://localhost:9292'
puts 'MCP endpoints:'
puts '  - http://localhost:9292/mcp/sse (SSE endpoint)'
puts '  - http://localhost:9292/mcp/messages (JSON-RPC endpoint)'
puts 'Press Ctrl+C to stop'

# Use the Puma server directly instead of going through Rack::Handler
require 'puma'
require 'puma/configuration'
require 'puma/launcher'

app = Rack::Builder.new { run mcp_app }
config = Puma::Configuration.new do |user_config|
  user_config.bind 'tcp://localhost:9292'
  user_config.app app
end

launcher = Puma::Launcher.new(config)
launcher.run
