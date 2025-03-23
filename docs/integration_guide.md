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
2. **Rack Middleware**: Embedding MCP directly in your web application as Rack middleware.

## Standalone Server Approach

The standalone approach runs the MCP server as a separate process:

```ruby
#!/usr/bin/env ruby
# mcp_server.rb

require 'fast_mcp'

# Create the server
server = MCP::Server.new(name: 'my-mcp-server', version: '1.0.0')

# Define tools
server.tool "example_tool" do
  description "An example tool"
  argument :input, description: "Input value", type: :string, required: true
  
  call do |args|
    "You provided: #{args[:input]}"
  end
end

# Register resources
server.register_resource(MCP::Resource.new(
  uri: "example/counter",
  name: "Counter",
  description: "A simple counter resource",
  mime_type: "application/json",
  content: JSON.generate({ count: 0 })
))

# Start the server
server.start
```

Then, in your application, you can connect to this server:

```ruby
require 'fast_mcp'

# Create a client
client = MCP::Client.new(name: 'my-client', version: '1.0.0')

# Connect to the server
client.connect('ruby mcp_server.rb')

# Call a tool
result = client.call_tool('example_tool', { input: 'Hello, world!' })
puts result

# Read a resource
resource = client.read_resource('example/counter')
counter_data = JSON.parse(resource[:content])
puts "Counter value: #{counter_data['count']}"
```

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

# Create the middleware
mcp_middleware = MCP.rack_middleware(app, name: 'my-mcp-server', version: '1.0.0') do |server|
  # Define your tools here
  server.tool "example_tool" do
    description "An example tool"
    argument :input, description: "Input value", type: :string, required: true
    
    call do |args|
      "You provided: #{args[:input]}"
    end
  end
  
  # Register resources here
  server.register_resource(MCP::Resource.new(
    uri: "example/counter",
    name: "Counter",
    description: "A simple counter resource",
    mime_type: "application/json",
    content: JSON.generate({ count: 0 })
  ))
end

# Use the middleware
use mcp_middleware
```

Clients can connect to this server using HTTP/SSE:

```ruby
require 'fast_mcp'

# Create a client
client = MCP::Client.new(name: 'my-client', version: '1.0.0')

# Connect to the server
client.connect_http('http://localhost:3000')

# Call a tool
result = client.call_tool('example_tool', { input: 'Hello, world!' })
puts result

# Read a resource
resource = client.read_resource('example/counter')
counter_data = JSON.parse(resource[:content])
puts "Counter value: #{counter_data['count']}"

# Subscribe to resource updates
client.subscribe_to_resource('example/counter') do |updated_resource|
  updated_data = JSON.parse(updated_resource[:content])
  puts "Counter updated: #{updated_data['count']}"
end
```

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
- [Hanami Integration Guide](./hanami_integration.md)

## Authentication and Authorization

Both integration approaches support authentication and authorization:

### Standalone Server Authentication

For standalone servers, you can implement authentication by checking credentials before processing requests:

```ruby
server.tool "secure_tool" do
  description "A secure tool that requires authentication"
  argument :api_key, description: "API key for authentication", type: :string, required: true
  argument :input, description: "Input value", type: :string, required: true
  
  call do |args|
    # Check the API key
    unless args[:api_key] == ENV['API_KEY']
      raise "Invalid API key"
    end
    
    # Process the request
    "You provided: #{args[:input]}"
  end
end
```

For resources, you can implement access control in the resource handlers:

```ruby
# Handle resources/read request with authentication
def handle_resources_read(params, id)
  uri = params['uri']
  api_key = params['api_key']
  
  # Check authentication
  unless api_key && api_key == ENV['API_KEY']
    send_error(-32600, "Unauthorized", id)
    return
  end
  
  # Continue with normal resource handling
  # ...
end
```

### Rack Middleware Authentication

For Rack middleware, you can implement authentication by customizing the transport:

```ruby
class AuthenticatedMcpTransport < MCP::Transports::RackTransport
  def call(env)
    request = Rack::Request.new(env)
    
    # Check if the request is for MCP endpoints
    if request.path.start_with?(@path_prefix)
      # Implement your authentication logic
      if authenticated?(request)
        super
      else
        [401, { 'Content-Type' => 'application/json' }, [JSON.generate({ error: 'Unauthorized' })]]
      end
    else
      @app.call(env)
    end
  end
  
  private
  
  def authenticated?(request)
    # Implement your authentication logic
    api_key = request.env['HTTP_X_API_KEY']
    api_key == ENV['API_KEY']
  end
end

# Use the custom transport
server = MCP::Server.new(name: 'my-mcp-server', version: '1.0.0')
# Define your tools and resources...

use AuthenticatedMcpTransport.new(server, app)
```

## Working with Resources

MCP Resources provide a way to share and synchronize data between the server and clients. Here's how to use them:

### Creating and Registering Resources

```ruby
# Create a resource
resource = MCP::Resource.new(
  uri: "example/counter",
  name: "Counter",
  description: "A simple counter resource",
  mime_type: "application/json",
  content: JSON.generate({ count: 0 })
)

# Register the resource with the server
server.register_resource(resource)
```

### Updating Resources

```ruby
# Update a resource
counter_data = JSON.parse(resource.content)
counter_data["count"] += 1
server.update_resource("example/counter", JSON.generate(counter_data))
```

### Reading Resources from the Client

```ruby
# Read a resource
resource = client.read_resource("example/counter")
counter_data = JSON.parse(resource[:content])
puts "Counter value: #{counter_data['count']}"
```

### Subscribing to Resource Updates

```ruby
# Subscribe to resource updates
client.subscribe_to_resource("example/counter") do |updated_resource|
  updated_data = JSON.parse(updated_resource[:content])
  puts "Counter updated: #{updated_data['count']}"
end
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
