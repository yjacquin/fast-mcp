# Integrating MCP with Web Applications

This guide explains how to integrate the Model Context Protocol (MCP) with your web application using the Fast MCP library. The library supports both standalone operation and integration with existing web frameworks.

## Installation

Add the Fast MCP gem to your application's Gemfile:

```ruby
gem 'fast-mcp'
```

Then run:

```bash
bundle install
```

## Integration Approaches

Fast MCP supports two main integration approaches:

1. **Standalone Server**: Running MCP as a separate process, communicating via STDIO.
2. **Rack Middleware**: Embedding MCP directly in your web application as a Rack middleware.

## Standalone Server Approach

The standalone approach runs the MCP server as a separate process:

```ruby
#!/usr/bin/env ruby
# mcp_server.rb

require 'fast_mcp'

# Create the server
server = FastMcp::Server.new(name: 'my-mcp-server', version: '1.0.0')

# Define tools
class ExampleTool < Mcp::Tool
  description "An example tool"
  arguments do
   required(:input).filled(:string).description("Input value")
  end

  def call(input:)
    "You provided: #{input}"
  end
end

class HelloWorld < FastMcp::Resource
  uri "example/counter.txt"
  name "Counter"
  description "A simple Hello World resource"
  mime_type "application/txt"

  def content
    "Hello, World!"
  end
end
# register the tool
server.register_tool(ExampleTool)
# Register the resource
server.register_resource(HelloWorld)

# Start the server
server.start
```

Then, in your application, you can connect to this server:


### Advantages of the Standalone Approach

- **Isolation**: The MCP server runs in a separate process, providing better isolation.
- **Independent Scaling**: You can scale the MCP server independently of your main application.
- **Fault Tolerance**: If the MCP server crashes, it doesn't affect your main application.

### Disadvantages of the Standalone Approach

- **Operational Complexity**: You need to manage an additional process.
- **Communication Overhead**: Inter-process communication adds some overhead.

## Rack Middleware Approach

The Rack middleware approach embeds the MCP server directly in your web application:

```ruby
require 'fast_mcp'

class ExampleTool < Mcp::Tool
  description "An example tool"
  arguments do
   required(:input).filled(:string).description("Input value")
  end

  def call(input:)
    "You provided: #{input}"
  end
end

class HelloWorld < FastMcp::Resource
  uri "example/counter.txt"
  name "Counter"
  description "A simple Hello World resource"
  mime_type "application/txt"

  def content
    "Hello, World!"
  end
end

# Create the middleware
mcp_middleware = FastMcp.rack_middleware(app, name: 'my-mcp-server', version: '1.0.0' do |server|
  # Define your tools here
  server.register_tool(ExampleTool)
  server.register_resource(HelloWorld)
end

# alternatively, you can use an authenticated rack middleware to secure it with an API key
mcp_middleware = FastMcp.rack_middleware(app, name: 'my-mcp-server', version: '1.0.0' do |server|
  # Define your tools here
  server.register_tool(ExampleTool)
  server.register_resource(HelloWorld)
end

# Use the middleware
use mcp_middleware
```
Clients can then connect to this server using HTTP/SSE

### Advantages of the Rack Middleware Approach

- **Simplicity**: No need to manage a separate process.
- **Resource Sharing**: Share resources (e.g., database connections) with your main application.
- **Authentication Integration**: Reuse your application's authentication mechanisms.

### Disadvantages of the Rack Middleware Approach

- **Coupling**: Tightly couples your MCP implementation to your web framework.
- **Resource Contention**: MCP operations might impact your main application's performance.
- **Scaling Challenges**: May complicate scaling strategies if MCP and application have different scaling needs.

## Framework-Specific Integration

For framework-specific integration guides, see:

- [Rails Integration Guide](./rails_integration.md)
- [Sinatra Integration Guide](./sinatra_integration.md)

## Authentication and Authorization

Both integration approaches support authentication and authorization:

### Standalone Server Authentication

For standalone servers, you can implement authentication by checking credentials before processing requests:

```ruby
class ExampleTool < FastMcp::Tool
  description "A secure tool that requires authentication"
  arguments do
    required(:api_key).filled(:string)description("API key for authentication")
    required(:input).filled(:string).description("Input value")
  end

  def call(api_key:, input)
    # Check the API key
    unless api_key == ENV['API_KEY']
      raise "Invalid API key"
    end

    # Process the request
    { output: "You provided: #{input}" }
  end
end
```

## Working with Resources

MCP Resources provide a way to share and synchronize data between the server and clients. Here's how to use them:

### Creating and Registering Resources

```ruby
# Create a resource
class Counter < FastMcp::Resource
  uri "example/counter"
  resource_name "Counter"
  description "A simple counter resource"
  mime_type "application/json"

  def content
    # Read from file or database, or generate dynamically
    count = File.exist?('counter.txt') ? File.read('counter.txt').to_i : 0
    JSON.generate({ count: count })
  end
end

# Register the resource with the server
server.register_resource(Counter)
```

### Updating Resources

Since resources are stateless, updates are typically handled through tools:

```ruby
# Example tool that updates the counter
class IncrementCounterTool < FastMcp::Tool
  description 'Increment the counter'

  def call
    # Read current value
    current_count = File.exist?('counter.txt') ? File.read('counter.txt').to_i : 0

    # Increment and save
    new_count = current_count + 1
    File.write('counter.txt', new_count.to_s)

    # Notify that the resource has been updated
    notify_resource_updated("example/counter")

    { count: new_count }
  end
end
```

### Reading Resources from the Client

```ruby
# Read a resource
resource = client.read_resource("example/counter")
counter_data = JSON.parse(resource[:content])
puts "Counter value: #{counter_data['count']}"
```

For more details on working with resources, see the [Resources documentation](./resources.md).

## Deployment Considerations

When deploying your application with MCP integration, consider the following:

### For Standalone Servers

1. **Process Management**: Use a process manager (e.g., systemd, Docker) to ensure the MCP server stays running.
2. **Logging**: Configure proper logging for the MCP server.
3. **Monitoring**: Set up monitoring to detect if the MCP server becomes unresponsive.
4. **Resource Updates**: Consider the frequency of resource updates and their impact on performance.

### For Rack Middleware

1. **Server Requirements**: Ensure your web server supports SSE for real-time communication.
2. **Load Balancing**: Configure load balancers to handle SSE connections properly.
3. **Timeouts**: Set appropriate timeouts for SSE connections.
4. **Resource Synchronization**: In multi-process environments, ensure resource updates are synchronized across processes.

## Choosing the Right Approach

The best approach depends on your specific requirements:

- **Use the Standalone Approach if**:
  - You need strong isolation between your application and MCP.
  - You want to scale MCP independently.
  - You're concerned about MCP operations affecting your main application's performance.
  - You have resources that update very frequently.

- **Use the Rack Middleware Approach if**:
  - You want a simpler deployment.
  - You need to share resources with your main application.
  - You want to reuse your application's authentication mechanisms.
  - Your resources don't update too frequently.

For most applications, we recommend starting with the Rack middleware approach for simplicity, then moving to the standalone approach if you encounter performance or scaling issues.

## Next Steps

- Check out the [examples directory](../examples) for more examples of using MCP.
- Read the [Resources documentation](./resources.md) for more details on using MCP Resources.
- Explore the [advanced configuration options](./advanced_configuration.md) for customizing MCP behavior.
