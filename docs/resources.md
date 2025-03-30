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

You can create resources by inheriting from the `FastMcp::Resource` class:

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
  
  def initialize
    @count = 0
  end
  
  attr_accessor :count
  
  def content
    JSON.generate({ count: @count })
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

You can update a resource's content:

```ruby
# Update the counter resource
counter_resource = server.read_resource("example/counter")
counter_resource.instance.count += 1

# Notify the content has been updated
server.notify_resource_updated("example/counter")
```

### Removing Resources

You can remove resources from the server:

```ruby
# Remove a resource
server.remove_resource("example/counter")
```


## Custom Resource Types

You can create custom resource types by inheriting from `FastMcp::Resource` and implementing the required methods:

```ruby
# Custom resource type for weather data
class WeatherResource < FastMcp::Resource
  uri "weather/current"
  resource_name "Current Weather"
  description "Current weather conditions"
  mime_type "application/json"
  
  def initialize(location = "New York")
    @location = location
    @conditions = {
      temperature: 22.5,
      condition: "Sunny",
      humidity: 45,
      wind_speed: 10,
      location: @location,
      updated_at: Time.now.to_s
    }
  end
  
  def content
    JSON.generate(@conditions)
  end
  
  def update_content(new_content)
    parsed_content = JSON.parse(new_content, symbolize_names: true)
    @conditions.merge!(parsed_content)
    @conditions[:updated_at] = Time.now.to_s
  end
  
  # Custom method to update just the temperature
  def update_temperature(temp)
    @conditions[:temperature] = temp
    @conditions[:updated_at] = Time.now.to_s
  end
end

# Register the resource
server.register_resource(WeatherResource)

# Later, update just the temperature
WeatherResource.instance.update_temperature(25.5)
# Notify the resource has been updated
server.notify_resource_updated(WeatherResource.uri)
```

This custom resource type has:

1. Class-level methods to define URI, name, description, and MIME type
2. Instance variables to store state
3. A `content` method that returns the current state as JSON
4. An `update_content` method to handle updates

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

4. **Consider Performance**: For frequently updated resources, consider throttling updates to avoid overwhelming clients.

5. **Error Handling**: Implement proper error handling for resource operations, especially when dealing with external data sources.

6. **Security**: Be mindful of what data you expose through resources, especially in multi-tenant applications.

## Conclusion

MCP Resources provide a powerful way to share and synchronize data between servers and clients. By using resources alongside tools, you can build rich, interactive applications with real-time updates. 