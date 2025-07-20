# MCP Resources

This guide explains how to use the Resources feature of the Model Context Protocol (MCP) with the Fast MCP library.

## What are MCP Resources?

Resources in MCP are a way to share data between the server and clients. Unlike tools, which are used for executing actions, resources are used for sharing and synchronizing state. Resources can be:

- Static data (like configuration)
- Dynamic data that changes over time (like user data)
- Binary content (like images or files)
- Streaming data that updates frequently (like sensor readings)

Resources are identified by a unique URI and can be read, subscribed to, and updated.

## Resource Features

The Fast MCP library supports the following resource features:

- **Resource Registration**: Register resources with the server
- **Resource Reading**: Read resource content from the client
- **Resource Subscription**: Subscribe to resource updates
- **Resource Notifications**: Receive notifications when resources change
- **Binary Content**: Support for both text and binary content
- **Resource Metadata**: Access resource metadata without reading the content

## Server-Side Usage

### Creating and Registering Resources

You can create resources by inheriting from the `FastMcp::Resource` class. Resources are stateless and generate content dynamically:

```ruby
require 'fast_mcp'

# Create a server
server = FastMcp::Server.new(name: "my-mcp-server", version: "1.0.0")

# Create a resource by inheriting from FastMcp::Resource
class CounterResource < FastMcp::Resource
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
server.register_resource(CounterResource)
```

### Creating Resources from Files

You can create resources from files:

```ruby
# Create a resource from a file
image_resource = FastMcp::Resource.from_file(
  "path/to/image.png",
  name: "Example Image",
  description: "An example image resource"
)

# Register the resource with the server
server.register_resource(image_resource)
```

### Updating Resources

Since resources are stateless, updates are typically handled through tools that modify external state (files, databases, etc.) and then notify about resource changes:

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

### Removing Resources

You can remove resources from the server:

```ruby
# Remove a resource
server.remove_resource("example/counter")
```

## Custom Resource Types

You can create custom resource types by inheriting from `FastMcp::Resource` and implementing the required methods. Resources should be stateless and read from external sources:

```ruby
# Custom resource type for weather data
class WeatherResource < FastMcp::Resource
  uri "weather/current"
  resource_name "Current Weather"
  description "Current weather conditions"
  mime_type "application/json"

  def content
    # Generate dynamic content or read from external source
    JSON.generate({
      temperature: rand(15..30),
      condition: ['Sunny', 'Cloudy', 'Rainy'].sample,
      humidity: rand(30..70),
      wind_speed: rand(5..25),
      updated_at: Time.now.to_s
    })
  end
end

# Register the resource
server.register_resource(WeatherResource)

# To update weather data, you would typically use a tool that
# writes to a file or database, then notifies about the update
```

This approach ensures that:

1. Resources are stateless and don't hold in-memory state
2. Content is generated dynamically from external sources
3. Multiple instances can be created without conflicts
4. Resources are more suitable for distributed environments

## Integration with Web Frameworks

When integrating MCP resources with web frameworks like Rails, Sinatra, or Hanami, you can use the same approach as with tools. The resources will be exposed through the Rack middleware.

For more details on integrating with web frameworks, see:
- [Rails Integration Guide](./rails_integration.md)
- [Sinatra Integration Guide](./sinatra_integration.md)
- [Hanami Integration Guide](./hanami_integration.md)

## Best Practices

1. **Use Appropriate URIs**: Use descriptive, hierarchical URIs for your resources (e.g., "users/profiles/123").

2. **Set Correct MIME Types**: Always set the correct MIME type for your resources to ensure proper handling.

3. **Handle Binary Content Properly**: When dealing with binary content, be careful with encoding and decoding.

4. **Keep Resources Stateless**: Resources should not maintain in-memory state. Instead, read from files, databases, or other external sources.

5. **Use Tools for Updates**: Use MCP tools to modify external state and notify about resource changes.

6. **Error Handling**: Implement proper error handling for resource operations, especially when dealing with external data sources.

7. **Security**: Be mindful of what data you expose through resources, especially in multi-tenant applications.

## Conclusion

MCP Resources provide a powerful way to share and synchronize data between servers and clients. By keeping resources stateless and using tools for updates, you can build robust, scalable applications that work well in distributed environments.
